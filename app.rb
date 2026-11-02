require "sinatra"
require "csv"
require "json"
require "net/http"
require "uri"

INPUT_TSV  = File.join(__dir__, "data", "input.tsv")
OUTPUT_TSV = File.join(__dir__, "data", "output.tsv")
INDEX_FILE = File.join(__dir__, "data", ".index")
CONFIG_TSV = File.join(__dir__, "data", "config.tsv")
PREF_FILE  = File.join(__dir__, "data", ".pref")

# 住所検索の候補ピンの表示上限
MAX_CANDIDATES = 10

# 日本全国の都道府県（絞り込み欄の候補。自由入力も可）
PREFECTURES = %w[
  北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県
  茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県
  新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県
  静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県
  奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県
  徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 長崎県
  熊本県 大分県 宮崎県 鹿児島県 沖縄県
].freeze

# Sinatra の erb は自動エスケープしないため、ビュー用の h を用意する
helpers do
  def h(s)
    Rack::Utils.escape_html(s.to_s)
  end
end

unless File.exist?(INPUT_TSV)
  warn "data/input.tsv が見つかりません。作成してください。"
  exit 1
end

# input.tsv を読み込む（ヘッダー: 建物名<TAB>住所<TAB>都道府県(任意)）
def load_input
  rows = []
  # liberal_parsing: 住所に含まれるダブルクォートで 500 にならないようにする
  CSV.foreach(INPUT_TSV, headers: true, col_sep: "\t", liberal_parsing: true) do |row|
    rows << { name: row["建物名"], address: row["住所"], pref: row["都道府県"] }
  end
  rows
end

# 絞り込み用の「都道府県 市区町村」を読み書き（例: 愛知県名古屋市）
def read_pref
  return "" unless File.exist?(PREF_FILE)
  File.read(PREF_FILE).strip
end

def write_pref(pref)
  File.write(PREF_FILE, pref.to_s.strip)
end

# "愛知県 名古屋市" のようなスペース入りも1つの検索語として扱う
def search_query(pref, address)
  [pref, address].map { |s| s.to_s.strip }.reject(&:empty?).join(" ")
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
# 返り値: [{ lat:, lng:, title: }, ...]（ヒット順）
def geocode(query)
  return [] if query.nil? || query.strip.empty?

  uri = URI("https://msearch.gsi.go.jp/address-search/AddressSearch")
  uri.query = URI.encode_www_form(q: query)

  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                        open_timeout: 5, read_timeout: 5) do |http|
    http.get(uri.request_uri)
  end
  return [] unless res.is_a?(Net::HTTPSuccess)

  data = JSON.parse(res.body)
  data = [] unless data.is_a?(Array)
  return [] unless data.is_a?(Array)

  # 候補が多いと地図がピンで埋まるので最大 MAX_CANDIDATES 件に絞る
  data.filter_map { |item|
    # geometry.coordinates は [経度, 緯度] の順
    coords = item.dig("geometry", "coordinates")
    next unless coords.is_a?(Array) && coords.size >= 2

    lng, lat = coords
    next unless lat.is_a?(Numeric) && lng.is_a?(Numeric)

    { lat: lat, lng: lng, title: item["properties"]&.dig("title").to_s }
  }.first(MAX_CANDIDATES)
rescue StandardError => e
  warn "geocode error: #{e.class}: #{e.message}"
  []
end

# 出力TSVに1行追記（ヘッダーが無ければ付与）
def append_output(name, address, lat, lng)
  new_file = !File.exist?(OUTPUT_TSV) || File.zero?(OUTPUT_TSV)
  CSV.open(OUTPUT_TSV, "a", col_sep: "\t") do |csv|
    csv << ["建物名", "住所", "緯度", "経度"] if new_file
    csv << [name, address, lat, lng]
  end
end

# 緯度経度として妥当か（範囲チェック付き）
def valid_coord?(lat, lng)
  lat_f = Float(lat)
  lng_f = Float(lng)
  lat_f.between?(-90, 90) && lng_f.between?(-180, 180)
rescue ArgumentError, TypeError
  false
end

get "/" do
  @rows  = load_input
  @index = read_index
  @total = @rows.size
  @pref  = read_pref
  @prefectures = PREFECTURES

  if @index >= @total
    @done = true
    erb :index
  else
    @done     = false
    @current  = @rows[@index]
    # 行ごとの都道府県列 > 画面上の絞り込み欄 の順で優先
    @query    = search_query(@current[:pref].to_s.strip.empty? ? @pref : @current[:pref],
                             @current[:address])
    @candidates = geocode(@query)
    erb :index
  end
end

# 絞り込み（都道府県/市区町村）を保存して再読み込み
post "/pref" do
  write_pref(params[:pref])
  redirect "/"
end

post "/save" do
  rows  = load_input
  index = read_index
  current = rows[index]

  if current && valid_coord?(params[:lat], params[:lng])
    pref = current[:pref].to_s.strip.empty? ? read_pref : current[:pref]
    append_output(current[:name], search_query(pref, current[:address]),
                  format("%.6f", params[:lat].to_f), format("%.6f", params[:lng].to_f))
    write_index(index + 1)
  end
  redirect "/"
end

post "/skip" do
  rows  = load_input
  index = read_index
  current = rows[index]

  if current
    pref = current[:pref].to_s.strip.empty? ? read_pref : current[:pref]
    append_output(current[:name], search_query(pref, current[:address]), "SKIP", "SKIP")
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
