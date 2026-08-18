#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "隐私检查必须在 Git 仓库中运行。"
  exit 1
fi

files=$(git ls-files)
if [ -z "$files" ]; then
  echo "没有可检查的 Git 文件。"
  exit 1
fi

bad_paths=""
unexpected_paths=""
for file in $files; do
  case "$file" in
    build/*|sync/*|backups/*|work/*|*.userdb/*|*.userdb|*.userdb.*|\
    installation.yaml|user.yaml|custom_phrase.txt|quick_memory.tsv|quick_memory.tsv.*|\
    sogou_cloud_cache.tsv|sogou_cloud_cache.tsv.*|iflytek_*|*iflytek*|\
    legacy_wongdean*|*legacy_wongdean*|rime_ice_user*|melt_eng_user*|\
    *.bin|*.ldb|*.log|*.so|*.dylib|*.zip|*.tar|*.tar.*|*.bak|*.backup|*.tmp|\
    .DS_Store|LOCK|CURRENT|MANIFEST-*)
      bad_paths="$bad_paths\n$file"
      ;;
  esac

  case "$file" in
    .github/workflows/privacy-audit.yml|.gitignore|LICENSE|README.md|\
    THIRD_PARTY_NOTICES.md|default.custom.yaml|rime_ice.custom.yaml|\
    squirrel.custom.yaml|docs/*.md|lua/*.lua|scripts/*.sh|scripts/*.py|\
    typo_corrections.dict.yaml|typo_corrections.schema.yaml|typo_corrections.tsv)
      ;;
    *) unexpected_paths="$unexpected_paths\n$file" ;;
  esac
done

if [ -n "$bad_paths" ]; then
  printf '发现禁止发布的运行时或个人文件：%b\n' "$bad_paths"
  exit 1
fi

if [ -n "$unexpected_paths" ]; then
  printf '发现不在公开白名单中的文件：%b\n' "$unexpected_paths"
  exit 1
fi

if git ls-files -ci --exclude-standard | grep -q .; then
  echo "发现已被 Git 跟踪、但后来才加入 .gitignore 的文件。"
  git ls-files -ci --exclude-standard
  exit 1
fi

if git grep -nE '/Users/[^/]+|namelessying|Library/Containers|Data/Downloads|BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]+|AKIA[0-9A-Z]{16}' \
  -- . ':(exclude)scripts/privacy_audit.sh'; then
  echo "发现本机路径、用户名或疑似凭据。"
  exit 1
fi

if git grep -niE '(password|passwd|cookie|authorization|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*[^[:space:]#]+' \
  -- . ':(exclude)scripts/privacy_audit.sh'; then
  echo "发现疑似凭据赋值。"
  exit 1
fi

echo "隐私扫描通过：Git 白名单、个人数据、二进制、本机路径与疑似凭据检查均通过。"
