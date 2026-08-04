#!/usr/bin/env bash
# マージ済みローカルブランチ・worktree の検出と削除。
# デフォルトは dry-run（削除しない）。実際に削除するには --apply を付ける。
# macOS 標準の bash 3.2 でも動くよう、連想配列・mapfile は使わない。
#
# Usage:
#   cleanup-merged.sh            # 計画を表示するだけ
#   cleanup-merged.sh --apply    # 実際に worktree/ブランチを削除する
# 注意: bash 3.2 (macOS 標準) は要素数0の配列を "${arr[@]}" で展開すると
# set -u 下で unbound variable エラーになるため、-u は付けない。
set -eo pipefail

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
MAIN_WORKTREE="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"

if [[ "$REPO_ROOT" != "$MAIN_WORKTREE" ]]; then
  echo "error: メイン作業ツリー ($MAIN_WORKTREE) で実行してください（現在: $REPO_ROOT）" >&2
  exit 1
fi
cd "$MAIN_WORKTREE"

DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)"
if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH="main"
fi

echo "== fetch --prune =="
git fetch origin --prune --quiet

HAVE_GH=1
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  HAVE_GH=0
  echo "warn: gh が使えないため squash merge されたブランチは検出できません（git --merged のみで判定）" >&2
fi

CURRENT_BRANCH="$(git branch --show-current)"

ALL_BRANCHES=()
while IFS= read -r line; do
  [[ -n "$line" && "$line" != "$DEFAULT_BRANCH" ]] && ALL_BRANCHES+=("$line")
done < <(git branch --format='%(refname:short)')

MERGED=()
MERGED_REASON=()   # 同じ index の MERGED[i] に対応する理由
UNMERGED=()

for b in "${ALL_BRANCHES[@]}"; do
  if git merge-base --is-ancestor "$b" "origin/$DEFAULT_BRANCH" 2>/dev/null; then
    MERGED+=("$b")
    MERGED_REASON+=("git-merged")
    continue
  fi
  matched=0
  if [[ "$HAVE_GH" == "1" ]]; then
    pr_info="$(gh pr list --state merged --head "$b" --json number,mergedAt -q '.[0] // empty' 2>/dev/null || true)"
    if [[ -n "$pr_info" ]]; then
      MERGED+=("$b")
      MERGED_REASON+=("gh-pr:$pr_info")
      matched=1
    fi
  fi
  [[ "$matched" == "0" ]] && UNMERGED+=("$b")
done

echo
echo "== マージ済みと判定したブランチ =="
if [[ ${#MERGED[@]} -eq 0 ]]; then
  echo "(なし)"
else
  i=0
  for b in "${MERGED[@]}"; do
    echo "  $b  (${MERGED_REASON[$i]})"
    i=$((i + 1))
  done
fi

echo
echo "== マージ未確認のためスキップするブランチ =="
if [[ ${#UNMERGED[@]} -eq 0 ]]; then
  echo "(なし)"
else
  printf '  %s\n' "${UNMERGED[@]}"
fi

if [[ ${#MERGED[@]} -eq 0 ]]; then
  echo
  echo "削除対象がありません。終了します。"
  exit 0
fi

# worktree_branch_pairs[i] = "<branch>\t<path>" 形式で保持（連想配列の代わり）
worktree_branch_pairs=()
current_path=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *) current_path="${line#worktree }" ;;
    branch\ refs/heads/*)
      br="${line#branch refs/heads/}"
      worktree_branch_pairs+=("$br"$'\t'"$current_path")
      ;;
  esac
done < <(git worktree list --porcelain)

worktree_path_of() {
  local target="$1" pair br path
  for pair in "${worktree_branch_pairs[@]}"; do
    br="${pair%%$'\t'*}"
    path="${pair#*$'\t'}"
    if [[ "$br" == "$target" ]]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

TO_DELETE=()
SKIPPED_DIRTY=()

echo
echo "== worktree の状態確認 =="
for b in "${MERGED[@]}"; do
  wt="$(worktree_path_of "$b" || true)"
  if [[ -n "$wt" && "$wt" != "$MAIN_WORKTREE" ]]; then
    if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
      echo "  skip (dirty worktree): $b -> $wt"
      SKIPPED_DIRTY+=("$b")
      continue
    fi
    echo "  clean worktree to remove: $b -> $wt"
  fi
  TO_DELETE+=("$b")
done

if [[ "$APPLY" == "0" ]]; then
  echo
  echo "(dry-run) 実際に削除するには --apply を付けて再実行してください。"
  exit 0
fi

echo
echo "== 適用開始 =="

for b in "${TO_DELETE[@]}"; do
  wt="$(worktree_path_of "$b" || true)"
  if [[ -n "$wt" && "$wt" != "$MAIN_WORKTREE" ]]; then
    echo "removing worktree: $wt"
    git worktree remove "$wt"
  fi
done

is_current=0
for b in "${TO_DELETE[@]}"; do
  [[ "$b" == "$CURRENT_BRANCH" ]] && is_current=1
done

if [[ "$is_current" == "1" ]]; then
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "error: 現在のブランチ ($CURRENT_BRANCH) に未コミットの変更があるため checkout できません。中断します。" >&2
    exit 1
  fi
  echo "checking out $DEFAULT_BRANCH (current branch $CURRENT_BRANCH is merged)"
  git checkout "$DEFAULT_BRANCH"
  git pull --ff-only origin "$DEFAULT_BRANCH"
fi

for b in "${TO_DELETE[@]}"; do
  echo "deleting branch: $b"
  git branch -D "$b"
done

echo
echo "== 完了 =="
git worktree list
git branch -vv

if [[ ${#SKIPPED_DIRTY[@]} -gt 0 ]]; then
  echo
  echo "dirty worktree のためスキップしたブランチ: ${SKIPPED_DIRTY[*]}"
fi
if [[ ${#UNMERGED[@]} -gt 0 ]]; then
  echo "マージ未確認のためスキップしたブランチ: ${UNMERGED[*]}"
fi
