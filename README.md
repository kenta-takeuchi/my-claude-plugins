# my-claude-plugins

個人用の Claude Code plugin marketplace。`my-skills` プラグインに全スキルをまとめている。

## 導入（新しいPCでのセットアップ）

1. リポジトリを clone する（このリポジトリと同じ絶対パスにする。ghq を使っている場合は以下だけでよい）。

   ```
   ghq get git@github.com:kenta-takeuchi/my-claude-plugins.git
   ```

2. `~/.claude/settings.json` に以下を追記する。

   ```json
   {
     "extraKnownMarketplaces": {
       "my-claude-plugins": {
         "source": {
           "source": "directory",
           "path": "/Users/<user>/ghq/github.com/kenta-takeuchi/my-claude-plugins"
         }
       }
     },
     "enabledPlugins": {
       "my-skills@my-claude-plugins": true
     }
   }
   ```

3. Claude Code を再起動するか `/plugin marketplace add <上記のpath>` を実行して認識させる。

## 更新の反映

このリポジトリを更新したら、各PCで `git pull`（directory source なので追加のコマンド不要。反映されない場合は `/plugin marketplace update`）。

## Plugins

### my-skills

- `write-issue`: 要望からGitHub Issueを作成
- `implement-issue`: Issue番号から実装〜PR作成まで一気通貫
- `pr-screenshots`: PRのスクリーンショットをPlaywrightで取得しPR本文に反映
- `cleanup-merged`: マージ済みブランチ・worktreeの一括削除
- `remove-worktree`: 現在のworktreeの後始末
