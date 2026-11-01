# address_to_latlon

住所から建物の中心座標（緯度経度）を取得するローカルWebアプリ。

TSVに書かれた「建物名,住所」を1件ずつ地図上に表示し、人間が地図をクリックして建物の中心を指定、その座標をTSVに書き出します。

## 必要環境

- WSL Ubuntu（または Linux / macOS）

- Ruby 3.3.6（rbenv 推奨）

- Bundler 4.0.16 以上


## セットアップ

```bash
git clone [https://github.com/kv1ro/address_to_latlon.git](https://github.com/kv1ro/address_to_latlon.git)
cd address_to_latlon

# gemをプロジェクト内にインストール（システム領域を汚さない）
bundle config set --local path vendor/bundle
bundle install
```

> `Gemfile.lock` はリポジトリに含めていません。`bundle install` 時に各環境で生成されます。

## 起動

```bash
bundle exec ruby app.rb -o 0.0.0.0 -p 4567
```

WindowsのChrome（またはブラウザ）で **http://localhost:4567** を開く。

`-o 0.0.0.0` はWSLからWindows側のブラウザでアクセスするために必要。

## 使い方

### 1. 入力データを用意

`data/input.tsv` を作成（**タブ区切り**、ヘッダー必須）：

```
建物名    住所
サンプルビル    東京都千代田区丸の内1-1
テストマンション    大阪府大阪市北区梅田3-1-1
```

Googleスプレッドシートからセルをコピー＆ペーストすると、そのままTSVとして貼り付けられます。

> ヘッダー名は「建物名」「住所」の2列にしてください。建物名・住所にカンマが含まれていても、TSVなら壊れません。

### 2. アプリで座標を取得

1. 起動したアプリを開く
2. 地図（OSM）が現在の住所付近に自動でセンタリングされる
3. **建物の中心をクリック**してピンを立てる（ズレていたらピンをドラッグで微調整）
4. **「保存して次へ」** ボタンを押す
5. 繰り返す

操作ボタン：

| ボタン | 動作 |
|---|---|
| 保存して次へ | 現在の座標を `data/output.tsv` に追記し、次の建物へ（座標未入力時は押せない） |
| スキップ | 座標を取得せず `SKIP` として記録し、次の建物へ |
| 1つ戻る | 前の建物に戻る（`data/output.tsv` の最終行も削除） |

### 3. 結果を確認

`data/output.tsv` に以下の形式で出力されます（タブ区切り）：

```
建物名    住所    緯度    経度
サンプルビル    東京都千代田区丸の内1-1    35.681236    139.767125
テストマンション    大阪府大阪市北区梅田3-1-1    SKIP    SKIP
```

座標が取得できなかった建物は `SKIP` と記録されます。

## データファイルの扱い

| ファイル | 役割 | Git管理 |
|---|---|---|
| `data/input.tsv` | 入力データ（建物名,住所）※タブ区切り | サンプルのみコミット、本番データは各自用意 |
| `data/output.tsv` | 出力結果（座標付き）※タブ区切り | 追記される。Git管理外 |
| `data/.index` | 進捗（何件目まで処理したか） | Git管理外。途中再開に使う |

**注意**：`data/output.tsv` をExcelで開いたままにしないでください。ファイルがロックされて書き込みに失敗します。

## 地図について

- [Leaflet](https://leafletjs.com/) を使用

- **デフォルトはOpenStreetMap**（建物名が表示されやすい）

- 航空写真・標準地図は[国土地理院](https://www.gsi.go.jp/)のタイル（APIキー不要・無料）

- 右上のレイヤ切替で「OSM」「航空写真」「標準地図」を切り替え可能

- 住所検索には[国土地理院の住所検索API](https://msearch.gsi.go.jp/address-search/AddressSearch)を使用


建物名が地図に出ない場合は、レイヤを「航空写真」に切り替えて屋根の形から判断してください。

## 進捗のリセット

最初からやり直したいとき：

```bash
echo 0 > data/.index
rm -f data/output.tsv
```

`input.tsv` を差し替えたときも、必ず進捗をリセットしてください。

## トラブルシューティング

### `Could not find ... in locally installed gems`

`bundle install` を実行してください。

```bash
bundle install
```

### `PermissionError ... /usr/lib/ruby/gems/...`

Bundlerがシステム領域に書き込もうとしています。以下を実行：

```bash
bundle config set --local path vendor/bundle
bundle install
```

### `cannot load such file -- csv / erb`

Rubyが3.4系になっていないか確認してください（3.3.6が必要）。

```bash
ruby -v
```

### `data/input.tsv が見つかりません`

`data/input.tsv` を作成してください（ヘッダー：`建物名<TAB>住所`）。

### 起動してもすぐ「全部終わったよ」と表示される

`data/.index` が入力件数以上になっています。リセットしてください。

```bash
echo 0 > data/.index
```

### Windowsのブラウザから `localhost:4567` に繋がらない

- `-o 0.0.0.0` を付けて起動しているか確認

- 起動ログに `Listening on http://0.0.0.0:4567` と出ているか確認

- WSL内で `curl -I http://localhost:4567` が通るか確認


### 地図に建物名が出ない

OSMに建物名が登録されていない建物です。「航空写真」レイヤに切り替えて、屋根の形と住所から判断してください。

## ライセンス

社内利用想定。外部公開時は別途検討。
