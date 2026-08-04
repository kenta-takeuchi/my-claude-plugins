---
name: cleanup-merged
description: マージ済みのローカルブランチと、それに紐づく git worktree をまとめて削除するときに使う。「マージ済みのブランチとworktreeを削除して」「使い終わったworktreeを片付けたい」「もう要らないブランチを一括で消して」が典型的なトリガー。squash merge でも GitHub 上でマージ済みと確認できたブランチを対象にする。単一の worktree だけを片付けたい場合は remove-worktree を使う（このスキルは複数ブランチ・複数worktreeの一括掃除が対象）。
disable-model-invocation: false
---

# cleanup-merged

リポジトリ内の**マージ済みローカルブランチ**と、それに紐づく**git worktree**を一括で削除する Skill。
squash merge 運用（`git branch --merged` では検出できない）を前提に、通常マージは `git merge-base --is-ancestor` で、
それで拾えないものは GitHub 上のマージ済み PR（`gh pr list`）で判定する。

判定・削除の手順は決まった git 操作なので `scripts/cleanup-merged.sh` に切り出してある。**手作業で git コマンドを打たず、このスクリプトを使うこと。**

## 使い方

```bash
# 1. まず dry-run で計画を確認する（デフォルトは削除しない）
bash <skill_dir>/scripts/cleanup-merged.sh

# 2. 計画に問題なければ適用する
bash <skill_dir>/scripts/cleanup-merged.sh --apply
```

`<skill_dir>` はこの SKILL.md が置かれているディレクトリ（`~/.claude/skills/cleanup-merged`）。

## 前提条件

1. リポジトリのメイン作業ツリー（プロジェクトのルート）で実行する。worktree の中から実行するとスクリプトがエラーで中断する。
2. `gh` コマンドが使えること（`gh auth status`）を推奨。使えない場合スクリプトは自動で警告を出し、`git merge-base` で判定できる通常マージのみを対象にする（squash merge されたブランチは取りこぼす）。

## スクリプトがやること

1. `git fetch origin --prune`
2. デフォルトブランチ以外の全ローカルブランチについて、マージ済みか判定する
   - `git merge-base --is-ancestor <branch> origin/<default>` → 通常マージ
   - それで判定できなければ `gh pr list --state merged --head <branch>` → squash merge も含めて確認
   - どちらでも確認できなければ「マージ未確認」として対象から除外する
3. マージ済みブランチのうち worktree が紐づくものは `git status --porcelain` で clean か確認し、dirty ならそのブランチ自体を削除対象から外してスキップ表示する（`--force` はしない）
4. （`--apply` 時のみ）clean な worktree を `git worktree remove`
5. （`--apply` 時のみ）現在のブランチが削除対象に含まれる場合、tracked ファイルに差分が無いことを確認してからデフォルトブランチへ `checkout` + `pull --ff-only`
6. （`--apply` 時のみ）残ったマージ済みブランチを `git branch -D`
7. 結果（削除した worktree・ブランチ、スキップしたブランチとその理由）を表示する

## 呼び出し側がやること

- スクリプトの dry-run 出力（マージ済み一覧・マージ未確認一覧・worktree の状態）をそのままユーザーに提示できる形で報告する。
- 「マージ未確認」に挙がったブランチは削除しない。未マージか、PR を経由しない個人作業ブランチかもしれないため、扱いをユーザーに確認する。
- dirty な worktree があってスキップされた場合、そのブランチも残る旨をユーザーに伝える。

## やらないこと

- デフォルトブランチ（`main`/`master`）は削除しない。
- GitHub 上でマージ済み PR が確認できず `git merge-base` でも判定できないブランチは削除しない。
- worktree が dirty な場合に `--force` で強制削除しない。
- リモートブランチの削除は行わない（対象はローカルブランチと worktree のみ）。
