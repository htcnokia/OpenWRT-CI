#!/bin/sh
# ZN-HomeProxy V8.3.10 (POSIX sh; CI runs the script with `sh`, not bash)
#
# Changelog vs earlier versions:
#   - V8.3.10: dropped deprecated `with_ech` from GO_PKG_TAGS. sing-box
#     1.14+ moved ECH into the standard library; keeping the tag triggers
#     ech_tag_stub.go: "cannot use \"...deprecated...\" as int value".
#     Full ECH is now built in without any tag.
#   - V8.3.4: base version feeding conflict cleanup, curl(23) fix.
#   - ... V8.3.5 fixed "}););" residual tails in generate_client.uc patch
#     (find_objects now consumes cross-line ");" statement tails).
#   - V8.3.6: sing-box package now sets GO_PKG_TAGS (with_utls etc.) so
#     Reality nodes do not FATAL with "uTLS ... not included in this
#     build"; injects version ldflags so "sing-box version" reports a
#     real version instead of "unknown".
#   - V8.3.7: full POSIX rewrite. The CI runner executes this file with
#     `sh` (dash); bash-only syntax (set -euo pipefail, declare -A,
#     arrays, read -d '', process substitution < <(...)) was rejected
#     with "set: Illegal option -o pipefail". All constructs are now
#     POSIX-compliant. Function/behavior is otherwise unchanged.
#
# Design:
#   1. Remove only known HomeProxy source locations.
#   2. Fetch upstream HomeProxy source.
#   3. Prefer szwjp/luci-app-homeproxy, fallback htcnokia/luci-app-homeproxy.
#   4. Keep sing-box version dynamic.
#   5. Generate OpenWrt sing-box source package from release tarball.
#   6. Download required SRS files at build time.
#   7. Localize only built-in RuleSets (full statement replacement).
#   8. Keep upstream HomeProxy logic untouched.
#   9. Persist /etc/homeproxy/private_srs through sysupgrade.
set -eu
ROOT="${1:-${GITHUB_WORKSPACE:-.}}"
ROOT="$(cd "$ROOT" && pwd)"
PRIMARY_REPO="https://github.com/szwjp/luci-app-homeproxy.git"
FALLBACK_REPO="https://github.com/htcnokia/luci-app-homeproxy.git"
HP_BRANCH="${ZN_HOMEPROXY_BRANCH:-}"
PACKAGE_DIR="$ROOT/package"
TARGET_DIR="$PACKAGE_DIR/luci-app-homeproxy"
CUSTOM_PACKAGE_DIR="$ROOT/package/custom"
SINGBOX_PACKAGE_DIR="$CUSTOM_PACKAGE_DIR/sing-box"
TMP_ROOT="$ROOT/.zn-homeproxy-tmp"
TMP_HP="$TMP_ROOT/luci-app-homeproxy"
SRS_DIR="$TARGET_DIR/root/etc/homeproxy/private_srs"
# V8.3.8: create TMP_ROOT up-front, after TMP_ROOT is defined. V8.3.7
# only mkdir'ed it inside fetch_homeproxy(), so
# remove_conflicting_singbox()'s redirect to
# "$TMP_ROOT/singbox_conflicts.txt" failed in CI with
# "cannot open ... No such file" because TMP_ROOT did not exist yet.
mkdir -p "$TMP_ROOT"
SYSUPGRADE_FILE="$ROOT/package/base-files/files/etc/sysupgrade.conf"
SINGBOX_VERSION=""
SINGBOX_API="https://api.github.com/repos/SagerNet/sing-box/releases/latest"

# POSIX replacement for the previous bash associative array. Each line is
# "<local-srs-filename>|<download-url>". Order is preserved for logging.
SRS_LIST='
cn.srs|https://fastly.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@rule-set/cn.srs
geosite-geolocation-cn.srs|https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set-unstable/geosite-geolocation-cn.srs
geosite-geolocation-!cn.srs|https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set-unstable/geosite-geolocation-!cn.srs
geosite-google.srs|https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-google.srs
geosite-openai.srs|https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-openai.srs
geosite-anthropic.srs|https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-anthropic.srs
geosite-whatsapp.srs|https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-whatsapp.srs
geosite-zoom.srs|https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-zoom.srs
'

log() {
	printf '[ZN-HomeProxy] %s\n' "$1"
}
warn() {
	printf '[ZN-HomeProxy][WARN] %s\n' "$1"
}
die() {
	printf '[ZN-HomeProxy][ERROR] %s\n' "$1"
	exit 1
}
pass() {
	printf '[ZN-HomeProxy][PASS] %s\n' "$1"
}
require_command() {
	local cmd="$1"
	command -v "$cmd" >/dev/null 2>&1 ||
		die "Required command not found: $cmd"
}
is_homeproxy_lineage() {
	local dir="$1"
	local makefile="$dir/Makefile"
	[ -f "$makefile" ] || return 1
	grep -Eq \
		'(^|[[:space:]])PKG_NAME:?=[[:space:]]*luci-app-homeproxy([[:space:]]|$)|(^|[[:space:]])LUCI_PKGARCH:?=[[:space:]]*all' \
		"$makefile"
}
repo_origin_matches() {
	local dir="$1"
	local expected="$2"
	local origin=""
	[ -d "$dir/.git" ] || return 1
	origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
	[ "$origin" = "$expected" ] ||
		[ "$origin" = "${expected%.git}" ] ||
		[ "$origin" = "${expected%.git}/" ]
}
remove_existing_homeproxy() {
	local path=""
	log "Scanning known HomeProxy locations..."
	for path in \
		"$PACKAGE_DIR/luci-app-homeproxy" \
		"$PACKAGE_DIR/custom/luci-app-homeproxy" \
		"$ROOT/feeds/luci/luci-app-homeproxy"
	do
		if [ -d "$path" ]
		then
			log "Removing: $path"
			rm -rf -- "$path"
		fi
	done
	mkdir -p "$PACKAGE_DIR"
	rm -rf "$TARGET_DIR"
}
remove_conflicting_singbox() {
	local path=""
	local list="$TMP_ROOT/singbox_conflicts.txt"
	log "Scanning conflicting sing-box packages..."
	# POSIX: no process substitution or read -d ''; use newline list.
	find \
		"$ROOT/package" \
		"$ROOT/feeds" \
		\( -type d -o -type l \) \
		-name sing-box \
		! -path "$CUSTOM_PACKAGE_DIR/sing-box" \
		2>/dev/null > "$list" || true
	while IFS= read -r path
	do
		[ -n "$path" ] || continue
		log "Removing conflicting sing-box: $path"
		rm -rf -- "$path"
	done < "$list"
	rm -f "$list"
	rm -f "$ROOT/feeds/packages.index"
	rm -rf "$ROOT/feeds/packages.tmp"
	pass "Conflicting sing-box cleanup completed"
}
fetch_homeproxy() {
	local repo=""
	local clone_args=""
	mkdir -p "$TMP_ROOT"
	for repo in "$PRIMARY_REPO" "$FALLBACK_REPO"
	do
		rm -rf "$TMP_HP"
		log "Trying repository: $repo"
		# POSIX-safe arg assembly (no arrays)
		clone_args="clone --depth 1"
		if [ -n "$HP_BRANCH" ]
		then
			clone_args="$clone_args --branch $HP_BRANCH"
		fi
		clone_args="$clone_args $repo $TMP_HP"
		# shellcheck disable=SC2086
		if ! git $clone_args >/dev/null 2>&1
		then
			warn "Clone failed: $repo"
			continue
		fi
		if ! is_homeproxy_lineage "$TMP_HP"
		then
			warn "Invalid HomeProxy repository: $repo"
			rm -rf "$TMP_HP"
			continue
		fi
		rm -rf "$TARGET_DIR"
		mv "$TMP_HP" "$TARGET_DIR"
		if ! repo_origin_matches "$TARGET_DIR" "$repo"
		then
			warn "Unable to verify repository origin"
		fi
		pass "Using HomeProxy: $repo"
		return 0
	done
	die "Unable to fetch HomeProxy"
}
download_file() {
	local url="$1"
	local output="$2"
	local tmp="${output}.tmp"
	rm -f "$tmp"
	log "Downloading $(basename "$output")"
	curl \
		-fL \
		--retry 3 \
		--retry-delay 2 \
		--connect-timeout 20 \
		--max-time 180 \
		-sS \
		"$url" \
		-o "$tmp" ||
		die "Download failed: $url"
	[ -s "$tmp" ] ||
		die "Downloaded file empty: $url"
	if LC_ALL=C head -c 1024 "$tmp" |
		tr '[:upper:]' '[:lower:]' |
		grep -Eq \
		'<!doctype|<html|<body|404|accessdenied|error'
	then
		rm -f "$tmp"
		die "Invalid download response: $url"
	fi
	mv "$tmp" "$output"
}
download_srs() {
	local line=""
	local name=""
	local url=""
	mkdir -p "$SRS_DIR"
	# POSIX: iterate the pipe-delimited SRS list line by line.
	for line in $SRS_LIST
	do
		[ -n "$line" ] || continue
		name="${line%%|*}"
		url="${line#*|}"
		(
			download_file \
				"$url" \
				"$SRS_DIR/$name"
		) &
	done
	wait
}
patch_init_jail_mounts() {
	local init="$TARGET_DIR/root/etc/init.d/homeproxy"
	[ -f "$init" ] ||
		die "Missing homeproxy init script"
	if grep -q 'HP_DIR/private_srs' "$init"
	then
		log "Init jail mounts already include private_srs"
		return 0
	fi
	# V8.3.9: the upstream procd jail mount whitelist does not include
	# private_srs, so sing-box inside the jail cannot see the local SRS
	# files and crash-loops with:
	#   "parse rule-set[0]: open /etc/homeproxy/private_srs/cn.srs:
	#    no such file or directory"
	# Mount the directory into the jail next to certs/.
	sed -i \
	's|procd_add_jail_mount "\$HP_DIR/certs/"|procd_add_jail_mount "$HP_DIR/certs/"\n\t\t\tprocd_add_jail_mount "$HP_DIR/private_srs/"|' \
		"$init" ||
		die "Failed to patch init jail mounts"
	grep -q 'HP_DIR/private_srs' "$init" ||
		die "Init jail mount patch did not apply"
	pass "Init jail mounts patched (private_srs visible in jail)"
}
patch_rulesets() {
	local script="$TMP_ROOT/patch_rulesets.py"
	cat > "$script" <<'PY'
#!/usr/bin/env python3
import re
import sys
from pathlib import Path
hp = Path(sys.argv[1])
target = hp / "root/etc/homeproxy/scripts/generate_client.uc"
if not target.exists():
	raise SystemExit(
		f"Missing generate_client.uc: {target}"
	)
text = target.read_text(
	encoding="utf-8"
)
targets = {
	"geoip-cn":
		"cn.srs",
	"geosite-cn":
		"geosite-geolocation-cn.srs",
	"geosite-noncn":
		"geosite-geolocation-!cn.srs",
}
def find_matching_brace(src, opening):
	depth = 0
	i = opening
	state = "normal"
	while i < len(src):
		c = src[i]
		n = src[i + 1] if i + 1 < len(src) else ""
		if state == "normal":
			if c == "'":
				state = "single"
			elif c == '"':
				state = "double"
			elif c == "`":
				state = "backtick"
			elif c == "/" and n == "/":
				state = "line_comment"
				i += 1
			elif c == "/" and n == "*":
				state = "block_comment"
				i += 1
			elif c == "{":
				depth += 1
			elif c == "}":
				depth -= 1
				if depth == 0:
					return i
		elif state in (
			"single",
			"double",
			"backtick"
		):
			if c == "\\":
				i += 1
			elif (
				state == "single" and c == "'"
			) or (
				state == "double" and c == '"'
			) or (
				state == "backtick" and c == "`"
			):
				state = "normal"
		elif state == "line_comment":
			if c == "\n":
				state = "normal"
		elif state == "block_comment":
			if c == "*" and n == "/":
				state = "normal"
				i += 1
		i += 1
	raise ValueError(
		"unmatched brace"
	)
def find_objects(src):
	pattern = re.compile(
		r"push\s*\(\s*config\.route\.rule_set\s*,\s*\{"
	)
	result = []
	for m in pattern.finditer(src):
		start = m.start()
		opening = src.find(
			"{",
			start
		)
		closing = find_matching_brace(
			src,
			opening
		)
		end = closing + 1
		# ... V8.3.5 skip whitespace incl. newlines, then consume the
		# statement tail ");" which upstream may place on its own
		# line; V8.3.4 only ate a same-line ";" and left ");" behind,
		# producing "}););" syntax errors.
		while end < len(src) and src[end] in " \t\r\n":
			end += 1
		if end < len(src) and src[end] == ")":
			end += 1
			while end < len(src) and src[end] in " \t\r\n":
				end += 1
		if end < len(src) and src[end] == ";":
			end += 1
		result.append(
			(
				start,
				end,
				src[opening + 1:closing]
			)
		)
	return result
def extract_tag(body):
	m = re.search(
		r"\btag\s*:\s*['\"]([^'\"]+)['\"]",
		body
	)
	return m.group(1) if m else None
objects = find_objects(text)
found = {
	tag: []
	for tag in targets
}
for item in objects:
	tag = extract_tag(item[2])
	if tag in found:
		found[tag].append(item)
for tag, items in found.items():
	if len(items) != 1:
		raise SystemExit(
			f"RuleSet count error: {tag}"
		)
def make_local(tag, filename):
	return (
		"push(config.route.rule_set, {\n"
		"    type: 'local',\n"
		f"    tag: '{tag}',\n"
		"    format: 'binary',\n"
		f"    path: HP_DIR + '/private_srs/{filename}'\n"
		"});"
	)
replace = []
for tag, items in found.items():
	start, end, body = items[0]
	replace.append(
		(
			start,
			end,
			make_local(
				tag,
				targets[tag]
			)
		)
	)
for start, end, new in reversed(replace):
	text = (
		text[:start]
		+
		new
		+
		text[end:]
	)
target.write_text(
	text,
	encoding="utf-8"
)
print(
	"RuleSet localization completed"
)
PY
	chmod +x "$script"
	log "Patching HomeProxy RuleSets..."
	python3 "$script" "$TARGET_DIR" ||
		die "RuleSet patch failed"
	rm -f "$script"
}
validate_rulesets() {
	local file="$TARGET_DIR/root/etc/homeproxy/scripts/generate_client.uc"
	[ -f "$file" ] ||
		die "Missing generate_client.uc"
	for item in \
		"geoip-cn:cn.srs" \
		"geosite-cn:geosite-geolocation-cn.srs" \
		"geosite-noncn:geosite-geolocation-!cn.srs"
	do
		local tag="${item%%:*}"
		local srs="${item##*:}"
		grep -q \
			"tag: '$tag'" \
			"$file" ||
			die "Missing RuleSet: $tag"
		grep -q \
			"private_srs/$srs" \
			"$file" ||
			die "Missing local SRS path: $srs"
	done
	pass "RuleSet validation passed"
}
generate_singbox_package() {
	local pkg="$SINGBOX_PACKAGE_DIR"
	local version=""
	local api_json="$TMP_ROOT/singbox_release.json"
	log "Resolving latest sing-box version..."
	curl \
		-fL \
		--connect-timeout 20 \
		--max-time 60 \
		-sS \
		-H "Accept: application/vnd.github+json" \
		"$SINGBOX_API" \
		-o "$api_json" ||
		die "Unable to fetch sing-box release API"
	version="$(
		python3 -c \
		'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"].lstrip("v"))' \
		"$api_json"
	)"
	rm -f "$api_json"
	[ -n "$version" ] ||
		die "Unable to resolve sing-box version"
	SINGBOX_VERSION="$version"
	log "Detected sing-box version: $SINGBOX_VERSION"
	log "Generating sing-box package: $SINGBOX_VERSION"
	log "Computing real PKG_HASH for sing-box tarball..."
	local tar_url="https://codeload.github.com/SagerNet/sing-box/tar.gz/v${SINGBOX_VERSION}"
	local tar_file="$TMP_ROOT/sing-box-${SINGBOX_VERSION}.tar.gz"
	local pkg_hash=""
	curl -fL --connect-timeout 20 --max-time 300 -sS "$tar_url" -o "$tar_file" ||
		die "Unable to fetch sing-box tarball for hashing"
	pkg_hash="$(sha256sum "$tar_file" | awk '{print $1}')"
	rm -f "$tar_file"
	[ -n "$pkg_hash" ] ||
		die "Unable to compute PKG_HASH"
	log "PKG_HASH: $pkg_hash"
	rm -rf "$pkg"
	mkdir -p "$pkg"
	cat > "$pkg/Makefile" <<EOF
include \$(TOPDIR)/rules.mk
PKG_NAME:=sing-box
PKG_VERSION:=$SINGBOX_VERSION
PKG_RELEASE:=1
PKG_SOURCE:=sing-box-\$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/SagerNet/sing-box/tar.gz/v\$(PKG_VERSION)?
PKG_HASH:=$pkg_hash
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
GO_PKG:=github.com/sagernet/sing-box
GO_PKG_BUILD_PKG:=\$(GO_PKG)/cmd/sing-box
GO_PKG_TAGS:=with_gvisor,with_quic,with_utls,with_wireguard,with_clash_api,with_dhcp
GO_PKG_LDFLAGS_X:=github.com/sagernet/sing-box/constant.Version=v\$(PKG_VERSION)
include \$(INCLUDE_DIR)/package.mk
include \$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk
define Package/sing-box-default
  SECTION:=net
  CATEGORY:=Network
  TITLE:=The universal proxy platform
  URL:=https://sing-box.sagernet.org
  DEPENDS:=+ca-bundle +kmod-tun
  USERID:=sing-box=5566:sing-box=5566
endef
define Package/sing-box
  \$(Package/sing-box-default)
  TITLE+= (full)
  VARIANT:=full
  DEFAULT_VARIANT:=1
endef
define Package/sing-box/description
sing-box universal proxy platform.
endef
define Build/Compile
  \$(call GoPackage/Build/Compile)
endef
define Package/sing-box/install
	\$(INSTALL_DIR) \$(1)/usr/bin
	\$(INSTALL_BIN) \$(GO_PKG_BUILD_BIN_DIR)/sing-box \$(1)/usr/bin/sing-box
endef
\$(eval \$(call BuildPackage,sing-box))
EOF
	pass "Generated sing-box source package"
}
validate_singbox_package() {
	local file="$SINGBOX_PACKAGE_DIR/Makefile"
	[ -f "$file" ] ||
		die "Missing sing-box Makefile"
	grep -q \
		"PKG_NAME:=sing-box" \
		"$file" ||
		die "Invalid sing-box package"
	grep -q \
		"codeload.github.com/SagerNet/sing-box" \
		"$file" ||
		die "Invalid sing-box source"
	grep -q \
		"with_utls" \
		"$file" ||
		die "sing-box build tags missing (with_utls)"
	pass "sing-box package validation passed"
}
validate_homeproxy() {
	local init="$TARGET_DIR/root/etc/init.d/homeproxy"
	local gen="$TARGET_DIR/root/etc/homeproxy/scripts/generate_client.uc"
	[ -f "$init" ] ||
		die "Missing HomeProxy init script"
	[ -f "$gen" ] ||
		die "Missing generate_client.uc"
	pass "HomeProxy validation passed"
}
ensure_sysupgrade_persistence() {
	local line="/etc/homeproxy/private_srs/*"
	local tmp="${SYSUPGRADE_FILE}.tmp"
	mkdir -p \
		"$(dirname "$SYSUPGRADE_FILE")"
	if [ -f "$SYSUPGRADE_FILE" ] &&
		grep -Fxq "$line" "$SYSUPGRADE_FILE"
	then
		return 0
	fi
	if [ -f "$SYSUPGRADE_FILE" ]
	then
		cp \
			"$SYSUPGRADE_FILE" \
			"$tmp"
	else
		: > "$tmp"
	fi
	printf '%s\n' "$line" >> "$tmp"
	mv \
		"$tmp" \
		"$SYSUPGRADE_FILE"
	pass "sysupgrade persistence enabled"
}
validate_srs() {
	local line=""
	local name=""
	for line in $SRS_LIST
	do
		[ -n "$line" ] || continue
		name="${line%%|*}"
		[ -s "$SRS_DIR/$name" ] ||
			die "Missing SRS file: $name"
	done
	pass "All SRS files validated"
}
trap 'rm -rf "$TMP_ROOT"' EXIT
log "ZN-HomeProxy V8.3.9 starting"
require_command git
require_command curl
require_command python3
remove_existing_homeproxy
remove_conflicting_singbox
fetch_homeproxy
download_srs
validate_srs
patch_init_jail_mounts
patch_rulesets
validate_rulesets
generate_singbox_package
validate_singbox_package
log "Final sing-box version for this build: ${SINGBOX_VERSION:-unknown}"
validate_homeproxy
ensure_sysupgrade_persistence
pass "ZN-HomeProxy V8.3.9 completed successfully"
