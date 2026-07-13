# Sake — notes for Claude Code

うまかったお酒を記録するPWA。iPhoneのホーム画面に追加して使う想定。Traqr/Calendarと同じ「vanilla JS・単一HTML・フレームワークなし・Meiryoフォント」の作風（詳細はObsidianの `Claude\Rule\` を参照）。仕様の原典はObsidianの `Claude\⚪︎App-Idea\酒管理ソフト.md`。

## これはWebアプリ（PWA）。ネイティブ機能は使っていない

`index.html`だけで完結する純粋なブラウザアプリ。`require('electron')`のようなものは一切なく、`file://`で直接開いても動く（ただしService Workerの登録とPWAインストールはhttps/localhostのようなsecure contextでないと機能しない）。

## データの持ち方

- IndexedDB（DB名 `sakelog`）に `genres`（ジャンル）と `items`（お酒の記録、写真はBlobで直接格納）を保存。**端末内のみ**で完結し、他端末との同期は一切ない。
- 写真は「最初にトリムした正方形1枚」だけを保存する（元画像は保持しない）。再トリムしたい場合は写真を選び直す必要がある — これは意図的な仕様（Obsidianの元アイデアメモの「さいしょにどうトリムするか調整できる」という書き方に基づく判断）。
- バックアップはJSON書き出し/読み込み（設定シートから）。写真はBase64化してJSON内に埋め込む。読み込みは全置換で、直前の状態はセッション中のみ有効なメモリ上のスナップショットから「元に戻す」で復元できる（ページを閉じると復元不可）。

## GitHub Pagesでのデプロイ（サブパス配信の注意）

このリポジトリ（`AI-work`）のGitHub Pagesはルート直下から配信されるため、実際のURLは `https://yasuharashigeru.github.io/AI-work/Sake/` のようにサブパスになる。そのため`manifest.json`・`service-worker.js`・アイコンの参照は**すべて相対パス**にしてある。絶対パス（`/xxx`から始まるもの）を書くとサブパス配信で壊れるので、今後手を入れるときも相対パスを維持すること。

Service Workerはアプリシェル（`index.html`, `manifest.json`, アイコン）をcache-firstでキャッシュしてオフライン起動を可能にしている。中身を更新したときは`service-worker.js`の`CACHE_NAME`をバージョンアップしないと、古いキャッシュが残って更新が反映されない端末が出る。

## アイコンについて

`icon-180.png` / `icon-192.png` / `icon-512.png` はPowerShellの`System.Drawing`で生成した簡易プレースホルダー（緑の角丸背景に「酒」の文字）。ちゃんとしたアイコンに差し替えたくなったら、同じ3サイズで置き換えるだけでよい。

## 検証方法

- ローカルでは `npx serve .`（このディレクトリで）のような静的サーバーを立てて、Chrome DevTools のモバイルエミュレーションでCRUD・クロップ座標計算・IndexedDBの永続化（Applicationタブ）を確認できる。
- ただしカメラ/フォトライブラリからの写真選択、クロップの実際の指の動き、ホーム画面追加後のアイコン表示などの**iOS Safari固有の挙動はChromiumのシミュレーションでは代表できない**。GitHub Pagesにデプロイした実URLを実機iPhoneのSafariで開いての手動確認を経てから「動作確認済み」と判断すること（Chromium自動テストのみでの断定は避ける）。

## 未実装・既知の制約（v1時点）

- 複数端末同期なし（意図的な仕様、[[Rule/データ保存先の判断]]参照）。
- 写真の再トリムは不可（新しい写真を選び直す形になる）。
- ジャンル並び替えはドラッグ&ドロップではなく▲▼ボタン（タッチでのドラッグ実装を避けた簡易対応）。
