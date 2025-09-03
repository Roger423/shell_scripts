#!/bin/bash
# 检测并修复项目中的 Windows CRLF (\r\n) 换行符

PROJECT_DIR="."
FIX_MODE=false

# 参数解析
for arg in "$@"; do
    case "$arg" in
        --fix) FIX_MODE=true ;;
        *) PROJECT_DIR="$arg" ;;
    esac
done

echo "Scanning directory: $PROJECT_DIR"
[ "$FIX_MODE" = true ] && echo "Mode: FIX (will convert CRLF -> LF)" || echo "Mode: CHECK ONLY"

FOUND_FILES=()

# 遍历所有文件（排除 .git 目录）
while IFS= read -r -d '' file; do
    if grep -q $'\r' "$file"; then
        FOUND_FILES+=("$file")
        echo "[FOUND] Windows line ending detected in: $file"
        if [ "$FIX_MODE" = true ]; then
            sed -i 's/\r$//' "$file"
            echo "[FIXED] Converted to Unix line endings: $file"
        fi
    fi
done < <(find "$PROJECT_DIR" -type f ! -path "*/.git/*" -print0)

# 总结报告
if [ ${#FOUND_FILES[@]} -eq 0 ]; then
    echo "✅ No CRLF line endings found."
else
    echo "⚠️ Found ${#FOUND_FILES[@]} files with CRLF line endings."
    if [ "$FIX_MODE" = false ]; then
        echo "👉 Run again with --fix to convert them."
    fi
fi
