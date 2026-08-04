---
name: remove-worktree
description: 現在のセッションが作業している git worktree を後始末するときに使う。「この worktree を削除して」「作業を終えたので worktree を片付けてリポジトリのルートに戻りたい」「worktree を消してそのブランチに main 側でチェックアウトし直したい」が典型的なトリガー。やることは (1) いまいる worktree を remove、(2) メイン作業ツリー（リポジトリのルート）へ移動、(3) その worktree が使っていたブランチをメイン側でチェックアウト、の3つ。新しい worktree の作成や、別ブランチへの切り替えだけが目的のときには使わない。
disable-model-invocation: false
---

# remove-worktree

いま作業している git worktree を片付けて、**リポジトリのルート（メイン作業ツリー）でそのブランチをチェックアウトし直す** Skill。
ローカル確認しながら UI を反復したいとき（dev サーバを見ながら直すと worktree より pull 不要なルートの方が楽）などに使う。

## やること（3 ステップ）

1. いまいる worktree を `git worktree remove` で削除する
2. メイン作業ツリー（リポジトリのルート）へ移動する
3. その worktree が使っていたブランチを、ルート側で `git checkout` する

> 重要な順序: **ブランチを remove より先にルートでチェックアウトすることはできない**。
> git は同じブランチを 2 つの作業ツリーで同時にチェックアウトさせないため、
> 必ず「worktree を remove → ルートで checkout」の順で行う。

## 前提条件の確認（破壊的操作の前に必ず）

着手前に次を確認し、満たさなければ**中断してユーザーに報告**する（作業の取りこぼしを防ぐ）。

1. **本当に worktree の中にいるか**
   - `git rev-parse --show-toplevel`（現在地）と `git worktree list --porcelain` の先頭エントリ（= メイン作業ツリー）を比較する。
   - 一致していたら worktree ではなくルートにいる → このスキルは不要。その旨を伝えて終了。
2. **未コミットの変更が無いか**
   - `git status --porcelain` が空であること。空でなければ、勝手に `--force` せず中断し、
     「コミット / push / stash のどれをするか」をユーザーに確認する（差分を捨てない）。
3. **ブランチが push 済みか**（推奨）
   - `git status -sb` の `ahead`/`gone` を確認。未 push のコミットがあれば、消える訳ではない（ブランチは残る）が
     念のため push を促す。

## 手順

```bash
# --- 値を取得（worktree の中で実行）---
BRANCH=$(git branch --show-current)                                  # この worktree のブランチ
WT=$(git rev-parse --show-toplevel)                                  # この worktree の絶対パス
ROOT=$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -1)  # メイン作業ツリー
```

確認: `WT` が `.claude/worktrees/` 配下で、`ROOT` がリポジトリのルートであること。`BRANCH` が想定どおりか目視する。

### A. ハーネスの EnterWorktree セッションにいる場合（推奨）

このセッションが `EnterWorktree` で作った worktree にいるなら、まず `ExitWorktree` ツールで
セッションをルートへ戻す（自分が立っているディレクトリを直接 remove しようとする事故と、
session の cwd 依存キャッシュのズレを避けられる）。

> **`action: "remove"` を使ってはいけない**。ExitWorktree の remove は worktree ディレクトリだけでなく
> **ブランチごと削除する**（しかもベースに無いコミットがあると拒否される）。このスキルの目的は
> 「ブランチを残してルートでチェックアウトし直す」ことなので、必ず `keep` を使う。

1. `ExitWorktree` を `action: "keep"` で呼ぶ → worktree とブランチを残したままセッションをルートへ戻す。
2. ルートからまず worktree ディレクトリを削除し（ブランチは消えない）、続けてそのブランチをチェックアウト:
   ```bash
   git -C "$ROOT" worktree remove "$WT"   # ディレクトリのみ削除・ブランチは残る
   git -C "$ROOT" checkout "$BRANCH"
   ```

### B. 素のシェル / EnterWorktree セッションでない場合

```bash
cd "$ROOT"                 # 先にルートへ移動（自分のいる worktree は remove できない）
git worktree remove "$WT"  # worktree を削除（dirty なら拒否される。意図的なときだけ --force）
git checkout "$BRANCH"     # ルートでブランチをチェックアウト
```

> ルート側が別ブランチで未コミットの変更を抱えていると `git checkout` が衝突して失敗する。
> その場合は無理に進めず、ユーザーにルート側の状態の扱いを確認する。

## 完了確認

- `git worktree list` に削除した worktree が出ないこと。
- `git -C "$ROOT" branch --show-current` が `BRANCH` であること。
- 削除した `.claude/worktrees/<name>` ディレクトリが消えていること。

確認できたら「どの worktree を消し、ルートをどのブランチに切り替えたか」を 1〜2 行で報告する。

## やらないこと

- **ブランチの削除はしない**（worktree を消すだけ。ブランチはルートでチェックアウトして使い続ける）。
- 未コミットの変更がある状態での `--force` 削除を勝手にしない。
- 新しい worktree の作成や、worktree と無関係な単なるブランチ切り替えはこのスキルの対象外。
