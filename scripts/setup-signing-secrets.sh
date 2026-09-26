#!/bin/bash
set -euo pipefail

REPO="patrick-fu/vibekey-elements"
echo "==> Configuring GitHub Actions Signing & Notarization Secrets for: $REPO"

# 1. Check if gh CLI is authenticated
if ! gh auth status &>/dev/null; then
  echo "Error: gh CLI is not authenticated. Please run 'gh auth login' first." >&2
  exit 1
fi

# 2. Handle Certificate (.p12)
P12_FILE="${1:-}"

if [ -n "$P12_FILE" ] && [ -f "$P12_FILE" ]; then
  echo "==> Using existing .p12 certificate: $P12_FILE"
  read -s -p "Enter password for $P12_FILE: " P12_PASSWORD
  echo ""
  
  echo "==> Uploading APPLE_CERTIFICATE_P12_BASE64..."
  base64 -i "$P12_FILE" | gh secret set APPLE_CERTIFICATE_P12_BASE64 -R "$REPO"
  
  echo "==> Uploading APPLE_CERTIFICATE_PASSWORD..."
  echo -n "$P12_PASSWORD" | gh secret set APPLE_CERTIFICATE_PASSWORD -R "$REPO"
else
  echo ""
  echo "------------------------------------------------------------------"
  echo "未指定现成 .p12 文件，正在尝试从 macOS 钥匙串自动导出 Developer ID 证书..."
  echo "系统弹窗时，请输入您的 Mac 登录密码以允许导出私钥。"
  echo "------------------------------------------------------------------"
  echo ""
  
  TEMP_P12="$(mktemp "${TMPDIR:-/tmp}/vibekey_cert.XXXXXX.p12")"
  P12_PASSWORD=$(openssl rand -hex 16)
  trap 'python3 -c "import os; os.path.exists(\"$TEMP_P12\") and os.remove(\"$TEMP_P12\")"' EXIT
  
  if security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -P "$P12_PASSWORD" -o "$TEMP_P12"; then
    echo "==> 证书私钥成功导出！"
    echo "==> 正在上传 APPLE_CERTIFICATE_P12_BASE64 到 GitHub Secrets..."
    base64 -i "$TEMP_P12" | gh secret set APPLE_CERTIFICATE_P12_BASE64 -R "$REPO"
    
    echo "==> 正在上传 APPLE_CERTIFICATE_PASSWORD 到 GitHub Secrets..."
    echo -n "$P12_PASSWORD" | gh secret set APPLE_CERTIFICATE_PASSWORD -R "$REPO"
  else
    echo "Error: 导出失败或被取消。您也可以手动在“钥匙串访问”中导出 .p12 后重试：" >&2
    echo "  ./scripts/setup-signing-secrets.sh /path/to/DeveloperID.p12" >&2
    exit 1
  fi
fi

# 3. Ensure Notarization credentials are set
echo "==> 正在配置 Apple 开发者与公证凭证..."
echo -n "[REDACTED]" | gh secret set APPLE_ID -R "$REPO"
echo -n "[REDACTED]" | gh secret set APPLE_APP_SPECIFIC_PASSWORD -R "$REPO"
echo -n "9N7UKH59LC" | gh secret set APPLE_TEAM_ID -R "$REPO"
echo -n "Developer ID Application: Patrick Fu (9N7UKH59LC)" | gh secret set APPLE_DEVELOPER_IDENTITY -R "$REPO"

echo ""
echo "=================================================================="
echo "🎉 恭喜！全部 6 项 CI 签名与公证 Secrets 均已配置完成！"
echo "=================================================================="
gh secret list -R "$REPO"
