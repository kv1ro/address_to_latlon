require "sinatra"
require "csv"
require "json"
require "net/http"
require "uri"

set :bind, "127.0.0.1"
set :port, 4567

INPUT_TSV  = File.join(__dir__, "data", "input.tsv")
OUTPUT_TSV = File.join(__dir__, "data", "output.tsv")
INDEX_FILE = File.join(__dir__, "data", ".index")

unless File.exist?(INPUT_TSV)
  warn "data/input.tsv が見つかりません。作成してください。"
  exit 1
end

# input.tsv を読み込む（ヘッダー: 建物名<TAB>住所）
def load_input
  rows = []
  CSV.foreach(INPUT_TSV, headers: true, col_sep: "\t") do |row|
    rows << { name: row["建物名"], address: row["住所"] }
  end
  rows
end

# 進捗インデックスの読み書き
def read_index
  return 0 unless File.exist?(INDEX_FILE)
  File.read(INDEX_FILE).to_i
end

def write_index(i)
  File.write(INDEX_FILE, i.to_s)
end

# 国土地理院 住所検索APIで住所をジオコーディング
# 返り値: { lat:, lng: } または nil
def geocode(address)
  return nil if address.nil? || address.strip.empty?

  uri = URI("https://msearch.gsi.go.jp/address-search/AddressSearch")
  uri.query = URI.encode_www_form(q: address)

  res = Net::HTTP.get_response(uri)
  return nil unless res.is_a?(Net::HTTPSuccess)

  data = JSON.parse(res.body)
  return nil if data.empty?

  # geometry.coordinates は [経度, 緯度] の順
  lng, lat = data[0]["geometry"]["coordinates"]
  { lat: lat, lng: lng }
rescue StandardError => e
  warn "geocode error: #{e.class}: #{e.message}"
  nil
end

# 出力TSVに1行追記（ヘッダーが無ければ付与）
def append_output(name, address, lat, lng)
  new_file = !File.exist?(OUTPUT_TSV) || File.zero?(OUTPUT_TSV)
  CSV.open(OUTPUT_TSV, "a", col_sep: "\t") do |csv|
    csv << ["建物名", "住所", "緯度", "経度"] if new_file
    csv << [name, address, lat, lng]
  end
end

get "/" do
  @rows  = load_input
  @index = read_index
  @total = @rows.size

  if @index >= @total
    @done = true
    erb :index
  else
    @done     = false
    @current  = @rows[@index]
    @geo      = geocode(@current[:address])
    erb :index
  end
end

post "/save" do
  rows  = load_input
  index = read_index
  current = rows[index]

  lat = params[:lat]
  lng = params[:lng]

  if current && lat && lng && !lat.empty? && !lng.empty?
    append_output(current[:name], current[:address], lat, lng)
  end

  write_index(index + 1)
  redirect "/"
end

post "/skip" do
  rows  = load_input
  index = read_index
  current = rows[index]

  if current
    append_output(current[:name], current[:address], "SKIP", "SKIP")
  end

  write_index(index + 1)
  redirect "/"
end

post "/undo" do
  i = read_index
  if i > 0
    # output.tsv の最終行を削除（ヘッダーのみは残す）
    lines = File.readlines(OUTPUT_TSV, chomp: true)
    lines.pop if lines.size > 1
    File.write(OUTPUT_TSV, lines.join("\n") + "\n")
    write_index(i - 1)
  end
  redirect "/"
end
