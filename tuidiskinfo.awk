#!/usr/bin/awk -f

# "Parsing JSON in Forty Lines of Awk"
# by Mohamed Akram
# https://akr.am/blog/posts/parsing-json-in-forty-lines-of-awk
# slightly adjusted for mawk compatibility and usability

#
# Extract a JSON value in an object or array:
#
# name = decode_json_string(get_json_value(json, "author.name"))
# date = decode_json_string(get_json_value(json, "events.0.date"))
#
# Or an entire object:
#
# get_json_value(json, "dependencies", deps)
#
# for (name in deps)
# 	version = decode_json_string(deps[name])
#
# Or array:
#
# get_json_value(json, "payload.tree.items", items)
#
# for (i = 0; items[i]; i++) {
# 	get_json_value(items[i], null, item)
# 	type = decode_json_string(item["type"])
# 	name = decode_json_string(item["name"])
# }
#
function get_json_value( \
	s, key, a,
	skip, type, all, rest, isval, i, c, k, null \
) {
	if (match(s, /^[[:space:]]+/)) s = substr(s, RLENGTH+1)
	if (s == "") return ""
	type = substr(s, 1, 1)
	all = key == ""
	if (type != "{" && type != "[") {
		if (!all) die("invalid json array/object " s)
		if (!match(s, /^(null|true|false|"(\\.|[^\\"])*"|[.0-9Ee+-]+)/))
			die("invalid json value " s)
		return substr(s, 1, RLENGTH)
	}
	if (!all && (i = index(key, "."))) {
		rest = substr(key, i+1)
		key = substr(key, 1, i-1)
	}
	if ((isval = type == "[")) k = 0
	for (i = 2; i <= length(s); i += length(c)) {
		if (match(substr(s, i), /^[[:space:]]+/)) {
			c = substr(s, i, RLENGTH)
			continue
		}
		c = substr(s, i, 1)
		if (c == "}" || c == "]") break
		else if (c == ",") { if ((isval = type == "[")) ++k }
		else if (c == ":") isval = 1
		else {
			if (!all && k == key && isval)
				return get_json_value(substr(s, i), rest, a)
			c = get_json_value(substr(s, i), "", null, 1)
			if (all && !skip && isval) a[JSONLEN = k] = c
			if (c ~ /^"/ && !isval) k = substr(c, 2, length(c)-2)
		}
	}
	if ((type == "{" && c != "}") || (type == "[" && c != "]"))
		die("unterminated json array/object " s)
	if (all) return substr(s, 1, i)
}

function decode_json_string( \
	s,
	out, i, c \
) {
	if (s !~ /^"./ || substr(s, length(s), 1) != "\"")
		die("invalid json string " s)
	s = substr(s, 2, length(s)-2)
	while ((i = index(s, "\\")) != 0) {
		if (!((c = substr(s, i+1, 1)) in JSONESC))
			die("unknown json escape " substr(s, i, 2))
		out = out substr(s, 1, i-1) JSONESC[c]
		s = substr(s, i+2)
	}
	return out s
}

#
# TUIDiskInfo - Dumps CrystalDiskInfo-style details via smartmontools
#

function die(msg) {
	if (IN_TUI) leave_tui()
	printf "Error: %s\n", msg > "/dev/stderr"
	exit 1
}

function enter_tui() {
	if (system("tput smcup 2>/dev/null") != 0) printf "\033[?1049h"
	IN_TUI = 1
}

function leave_tui() {
	if (system("tput rmcup 2>/dev/null") != 0) printf "\033[?1049l"
	IN_TUI = 0
}

function cls() {
	printf "\033[H\033[2J"
}

function pause( \
	\
	d \
) {
	printf "Press Enter to continue..."
	system("")
	getline d < "/dev/tty"
}

function max(a, b) {
	return a > b ? a : b
}

function term_size( \
	\
	cmd, l, c \
) {
	LINES = 0
	COLS = 0
	cmd = "tput lines 2>/dev/null"
	if ((cmd | getline l) > 0) LINES = l + 0
	close(cmd)
	cmd = "tput cols 2>/dev/null"
	if ((cmd | getline c) > 0) COLS = c + 0
	close(cmd)
	if (LINES < 3) LINES = 24
	if (COLS < 20) COLS = 80
	DASH_C = substr(DASH, 1, COLS)
	BAR_C = substr(BAR, 1, COLS)
}

function buf_reset() {
	BUFN = 0
	split("", BUF)
}

function emit(s) {
	BUF[BUFN++] = s
}

function pager( \
	\
	top, rows, i, key, endln \
) {
	top = 0
	while (1) {
		term_size()
		rows = LINES - 1
		if (rows < 1) rows = 1
		cls()
		for (i = top; i < top + rows && i < BUFN; i++) print BUF[i]
		endln = (top + rows < BUFN) ? (top + rows) : BUFN
		printf "%s lines %d-%d/%d  [f/Enter] fwd  [b] back  [g] top  [G] bottom  [q] quit %s> ", \
			C_HEAD, top + 1, endln, BUFN, RESET
		system("")
		if ((getline key < "/dev/tty") <= 0) break
		if (key == "q" || key == "Q") break
		else if (key == "b" || key == "p") { top -= rows; if (top < 0) top = 0 }
		else if (key == "g") top = 0
		else if (key == "G") { top = BUFN - rows; if (top < 0) top = 0 }
		else if (top + rows < BUFN) top += rows
		else break
	}
}

function shq(s) {
	gsub(/'/, "'\\''", s)
	return "'" s "'"
}

function run( \
	cmd,
	line, out \
) {
	out = ""
	while ((cmd | getline line) > 0) out = out line "\n"
	close(cmd)
	return out
}

function gv( \
	json, path, o,
	v \
) {
	JSONLEN = -1
	v = get_json_value(json, path, o)
	JSONLEN = substr(v, 1, 1) != "[" ? -1 : JSONLEN + 1
	return v
}

function str( \
	json, path, def,
	v \
) {
	v = gv(json, path)
	return v == "" ? def : substr(v, 1, 1) == "\"" ? decode_json_string(v) : v
}

function num( \
	json, path,
	v \
) {
	v = gv(json, path)
	return v == "" ? 0 : v + 0
}

function has_smart_data(json) {
	gv(json, "ata_smart_attributes.table")
	if (JSONLEN > 0) return 1
	return gv(json, "nvme_smart_health_information_log") != ""
}

function smart_json( \
	name, type,
	json, i, r \
) {
	if (type == "") type = "auto"
	json = run("smartctl -a -j -d " shq(type) " " shq(name) " 2>/dev/null")
	if (!has_smart_data(json)) {
		for (i = 0; i != ALTTYPESLEN; i++) {
			if (ALTTYPES[i] == type) continue
			r = run("smartctl -a -j -d " ALTTYPES[i] " " shq(name) " 2>/dev/null")
			if (has_smart_data(r)) {
				return r
			}
		}
	}
	return json
}

function scan_devices( \
	\
	scan, devs, n, i, name, ndev, j, dev, found, darr \
) {
	NDEV = 0
	scan = run("smartctl --scan -j 2>/dev/null")
	if (substr(gv(scan, "devices", devs), 1, 1) == "[") {
		n = JSONLEN
		for (i = 0; i != n; i++) {
			name = str(devs[i], "name", "")
			if (name == "") continue
			if (system("test -b '" name "' || test -c '" name "'") != 0) continue
			DEV_NAME[NDEV] = name
			DEV_TYPE[NDEV] = str(devs[i], "type", "")
			NDEV++
		}
	}

	ndev = split(run("ls -1 /dev/sd* 2>/dev/null"), darr, "\n")
	for (i = 1; i <= ndev; i++) {
		dev = darr[i]
		if (dev == "") continue
		if (dev ~ /[0-9]$/) continue
		if (system("test -b '" dev "'") != 0) continue
		found = 0
		for (j = 0; j != NDEV; j++) {
			if (DEV_NAME[j] == dev) { found = 1; break }
		}
		if (found) continue
		if (has_smart_data(run("smartctl -a -j -d sat '" dev "' 2>/dev/null"))) {
			DEV_NAME[NDEV] = dev
			DEV_TYPE[NDEV] = "sat"
			NDEV++
		}
	}

	if (NDEV < 2) return
	for (i = 0; i != NDEV - 1; i++)
		for (j = i + 1; j != NDEV; j++)
			if (DEV_NAME[i] > DEV_NAME[j]) {
				name = DEV_NAME[i]; DEV_NAME[i] = DEV_NAME[j]; DEV_NAME[j] = name
				dev = DEV_TYPE[i]; DEV_TYPE[i] = DEV_TYPE[j]; DEV_TYPE[j] = dev
			}
}

function get_nvme_mode( \
	dev,
	base, syspath, speed, width, gen, ret \
) {
	base = dev
	sub(/^\/dev\//, "", base)
	sub(/n[0-9].*$/, "", base)

	syspath = "/sys/class/nvme/" base "/device/current_link_speed"
	ret = (getline speed < syspath) > 0
	close(syspath)
	if (ret) {
		gen = "?"
		if (speed ~ /2\.5/) gen = "1.0"
		else if (speed ~ /5\.0/) gen = "2.0"
		else if (speed ~ /8\.0/) gen = "3.0"
		else if (speed ~ /16\.0/) gen = "4.0"
		else if (speed ~ /32\.0/) gen = "5.0"
	} else {
		return "Unknown"
	}

	syspath = "/sys/class/nvme/" base "/device/current_link_width"
	ret = (getline width < syspath) > 0
	close(syspath)

	return ret ? "PCIe " gen " " width "x" : "PCIe " gen
}

function get_sata_mode( \
	dev,
	mode, cmd, line, gbs \
) {
	mode = "Unknown"
	cmd = "smartctl -i " shq(dev) " 2>/dev/null"
	while ((cmd | getline line) > 0) {
		if (line ~ /SATA Version is:/) {
			if (match(line, /[0-9]+\.[0-9]+ Gb\/s/)) {
				gbs = substr(line, RSTART, RLENGTH)
				mode = "SATA/?"
				if (gbs ~ /^6\.0/) mode = "SATA/600"
				else if (gbs ~ /^3\.0/) mode = "SATA/300"
				else if (gbs ~ /^1\.5/) mode = "SATA/150"
			}
		}
	}
	close(cmd)

	return mode
}

function attr_health(id, value, thresh, rawv, model) {
	if (id == 188 && substr(model, 1, 2) == "ST") return 0
	if (thresh != 0 && value < thresh) return 2
	if (rawv != 0 && id in CAUTION) return 1
	return 0
}

function smart_afr_value( \
	rates, value,
	idx \
) {
	idx = int(value) + 1
	if (idx < 1) idx = 1
	if (idx > SMARTLEN) idx = SMARTLEN
	return 365 / 30 * rates[idx]
}

function smart_afr( \
	json, model,
	afr, raws, tbl, n, i, id, raw, r \
) {
	afr = 0

	split("", raws)
	gv(json, "ata_smart_attributes.table", tbl)
	n = JSONLEN
	for (i = 0; i != n; i++) {
		id = num(tbl[i], "id")
		if (id in FAILID) raws[id] = num(tbl[i], "raw.value")
	}

	if ((raw = raws[5]) != "") {
		r = smart_afr_value(S5R, int(raw % 4294967296))
		if (afr < r) afr = r
	}

	if ((raw = raws[187]) != "") {
		r = smart_afr_value(S187R, int(raw % 65536))
		if (afr < r) afr = r
	}

	if (substr(model, 1, 2) != "ST" && (raw = raws[188]) != "") {
		r = smart_afr_value(S188R, int(raw % 65536))
		if (afr < r) afr = r
	}

	if ((raw = raws[197]) != "") {
		r = smart_afr_value(S197R, int(raw % 4294967296))
		if (afr < r) afr = r
	}

	if ((raw = raws[198]) != "") {
		r = smart_afr_value(S198R, int(raw % 4294967296))
		if (afr < r) afr = r
	}

	return afr
}

function poisson_prob(rate) {
	if (rate <= 0) return 0
	return 1 - exp(-rate)
}

function failure_prob( \
	json, model,
	afr \
) {
	afr = smart_afr(json, model)
	if (afr == 0) return ""
	return sprintf("%.1f%%", poisson_prob(afr) * 100)
}

function temperature_health(temp, type) {
	if (type == "HDD") return temp < 50 ? 0 : temp < 55 ? 1 : 2
	if (type == "SSD") return temp < 50 ? 0 : temp < 70 ? 1 : 2
	return temp < 60 ? 0 : temp < 75 ? 1 : 2 # NVMe SSD
}

function get_nvme_temp( \
	t, ts,
	tv \
) {
	if (t == "40" && substr(ts, 1, 1) == "[") {
		if ((tv = gv(ts, "1")) != "") return tv
	}
	return t
}

function device_health( \
	json,
	type, tbl, n, hmax, i, st, status, nvw, t, nvobj, nv, temp, model \
) {
	type = num(json, "rotation_rate") > 0 ? "HDD" : "SSD"
	model = str(json, "model_name", "")
	if (model == "") model = str(json, "scsi_model_name", "")
	gv(json, "ata_smart_attributes.table", tbl)
	n = JSONLEN
	hmax = 0
	for (i = 0; i < n; i++) {
		hmax = max(hmax, attr_health(num(tbl[i], "id"), num(tbl[i], "value"), \
			num(tbl[i], "thresh"), num(tbl[i], "raw.value"), model))
	}
	st = gv(json, "smart_status.passed")
	status = st == "false" ? 2 : 0
	nvw = 0
	t = gv(json, "temperature.current")
	if (gv(json, "nvme_smart_health_information_log", nvobj) != "") {
		nv = nvobj["critical_warning"]
		nvw = nv != "" && nv != "0" ? 1 : 0
		type = "NVMe"
		t = get_nvme_temp(t, nvobj["temperature_sensors"])
	}
	temp = t == "" ? 0 : temperature_health(t + 0, type)
	return HEALTH[max(max(hmax, temp), max(status, nvw))]
}

function ata_attr_raw( \
	tbl, n, id,
	i \
) {
	for (i = 0; i != n; i++)
		if (num(tbl[i], "id") == id) return num(tbl[i], "raw.value")
	return ""
}

function color_health( \
	word,
	c \
) {
	if (word == "Good") c = C_GOOD
	else if (word == "Bad") c = C_BAD
	else c = C_CAUTION
	return sprintf("%s%-7s%s", c, word, RESET)
}

function human_size( \
	bytes,
	i, s, n \
) {
	if (bytes == "") return "--"
	s = bytes + 0
	n = SIZESLEN
	i = 0
	while (s >= 1000 && i < n) {
		s /= 1000
		i++
	}
	return sprintf("%.1f %s", s, SIZES[i])
}

function print_header() {
	printf "%sTUIDiskInfo%s\n", C_TITLE, RESET
	printf "%s%s\n", C_HEAD, DASH_C
	printf " %-3s %-14s %-30s %6s  %-7s  %s\n", \
		"No", "Device", "Model", "Temp", "Health", "FP"
	printf "%s\n%s", DASH_C, RESET
}

function cache_device( \
	i,
	json, n, model, t, ts \
) {
	if (i in CACHED) return
	json = smart_json(DEV_NAME[i], DEV_TYPE[i])
	n = str(json, "model_name", "")
	model = CACHE_MODEL[i] = n == "" ? str(json, "scsi_model_name", "Unknown") : n
	t = gv(json, "temperature.current")
	if ((ts = gv(json, "nvme_smart_health_information_log.temperature_sensors")) != "") t = get_nvme_temp(t, ts)
	CACHE_TEMP[i] = t == "" || t == "0" ? "--" : t " C"
	CACHE_HEALTH[i] = device_health(json)
	CACHE_FP[i] = num(json, "rotation_rate") > 0 ? failure_prob(json, model) : ""
	CACHED[i] = 1
}

function cache_reset() {
	split("", CACHED)
}

function print_menu( \
	\
	i, rows, shown, pages, page, fp \
) {
	term_size()
	cls()
	print_header()
	rows = LINES - 7
	if (rows < 1) rows = 1
	MROWS = rows
	if (MTOP < 0 || MTOP >= NDEV) MTOP = 0
	shown = 0
	for (i = MTOP; i < NDEV && shown < rows; i++) {
		cache_device(i)
		fp = CACHE_FP[i]
		printf " %2d) %-14s %-30.30s %6s  %s  %s\n", \
			i + 1, DEV_NAME[i], CACHE_MODEL[i], CACHE_TEMP[i], color_health(CACHE_HEALTH[i]), \
			(fp == "" ? "--" : fp)
		shown++
	}
	print DASH_C
	pages = int((NDEV + rows - 1) / rows)
	page = int(MTOP / rows) + 1
	printf "Page %d/%d  [number] details  [n]ext [p]rev [r]efresh [q]uit\n", \
		page, pages
}

function emit_banner(name, model, health, status, t, firmware, serial, cap, rotation, poh, cycles, hr, hw, mode, fp) {
	emit(sprintf("%s%s%s", C_HEAD, BAR_C, RESET))
	emit(sprintf("%s %s  -  %s%s", C_HEAD, name, model, RESET))
	emit(sprintf("%s%s%s", C_HEAD, BAR_C, RESET))
	emit(sprintf(" %-16s: %s", "Health", color_health(health)))
	emit(sprintf(" %-16s: %s", "SMART Status", status))
	emit(sprintf(" %-16s: %s", "Temperature", t == "" || t == "0" ? "--" : t " C"))
	emit(sprintf(" %-16s: %s", "Firmware", firmware))
	emit(sprintf(" %-16s: %s", "Serial", serial))
	emit(sprintf(" %-16s: %s", "Capacity", human_size(cap)))
	emit(sprintf(" %-16s: %s", "Transfer Mode", mode))
	emit(sprintf(" %-16s: %s", "Rotation Rate", rotation))
	emit(sprintf(" %-16s: %s", "Power On Hours", poh))
	emit(sprintf(" %-16s: %s", "Power On Count", cycles))
	emit(sprintf(" %-16s: %s", "Host Reads", hr))
	emit(sprintf(" %-16s: %s", "Host Writes", hw))
	emit(sprintf(" %-16s: %s", "Failure Prob", fp == "" ? "--" : fp))
}

function sorted_keys( \
	of, out,
	i, j, temp, n, m \
) {
	split("", out)
	n = 0
	for (i in of) out[n++] = i

	if (n < 2) return n
	m = n - 1
	for (i = 0; i != m; i++)
		for (j = i + 1; j != n; j++)
			if (out[i] > out[j]) { temp = out[i]; out[i] = out[j]; out[j] = temp }

	return n
}

function print_details( \
	name, type,
	json, model, firmware, serial, cap, rr, rotation, poh, cycles, t, st,
	status, health, hr, hw, dur, duw, x, tbl, n, i, id, val, thr, rawv, raw, th,
	nvobj, k, v \
) {
	json = smart_json(name, type)
	model = str(json, "model_name", "")
	if (model == "") model = str(json, "scsi_model_name", "Unknown")
	firmware = str(json, "firmware_version", "--")
	serial = str(json, "serial_number", "--")
	cap = gv(json, "user_capacity.bytes")
	if (cap == "") cap = gv(json, "nvme_total_capacity")
	rr = num(json, "rotation_rate")
	rotation = rr > 0 ? rr " rpm" : "Solid State Device"
	poh = str(json, "power_on_time.hours", "--")
	cycles = str(json, "power_cycle_count", "--")
	t = gv(json, "temperature.current")
	st = gv(json, "smart_status.passed")
	status = st == "true" ? "PASSED" : st == "false" ? "FAILED" : "--"
	health = device_health(json)

	buf_reset()
	gv(json, "ata_smart_attributes.table", tbl)
	n = JSONLEN
	if (n > 0) {
		x = ata_attr_raw(tbl, n, 242); hr = x == "" ? "--" : human_size(x * BLOCKSIZE)
		x = ata_attr_raw(tbl, n, 241); hw = x == "" ? "--" : human_size(x * BLOCKSIZE)
		emit_banner(name, model, health, status, t, firmware, serial, cap, rotation, poh, cycles, hr, hw, get_sata_mode(name), failure_prob(json, model))
		emit(sprintf("%s%s%s", C_HEAD, DASH_C, RESET))
		emit(sprintf("%s %-7s %3s %-25s %4s %4s %4s  %s%s", \
			C_HEAD, "Health", "ID", "AttributeName", "Cur", "Wst", "Thr", "RawValue", RESET))
		emit(sprintf("%s%s%s", C_HEAD, DASH_C, RESET))
		for (i = 0; i != n; i++) {
			id = num(tbl[i], "id")
			val = num(tbl[i], "value")
			thr = num(tbl[i], "thresh")
			rawv = num(tbl[i], "raw.value")
			raw = str(tbl[i], "raw.string", "")
			if (raw == "") raw = rawv
			th = id == 194 ? temperature_health(t + 0, rr > 0 ? "SSD" : "HDD") : attr_health(id, val, thr, rawv, model)
			emit(sprintf(" %s %3d %-25.25s %4d %4d %4d  %s %s", \
				color_health(HEALTH[th]), \
				id, str(tbl[i], "name", ""), val, num(tbl[i], "worst"), thr, \
				id in INDICATORS ? INDICATORS[id] : "  ", raw))
		}
	} else if (gv(json, "nvme_smart_health_information_log", nvobj) != "") {
		dur = nvobj["data_units_read"]; hr = dur == "" ? "--" : human_size(dur * 1000 * BLOCKSIZE)
		duw = nvobj["data_units_written"]; hw = duw == "" ? "--" : human_size(duw * 1000 * BLOCKSIZE)
		emit_banner(name, model, health, status, get_nvme_temp(t, nvobj["temperature_sensors"]), firmware, serial, cap, rotation, poh, cycles, hr, hw, get_nvme_mode(name), "")
		emit(sprintf("%s%s%s", C_HEAD, DASH_C, RESET))
		emit(sprintf("%s NVMe Health Information Log%s", C_HEAD, RESET))
		emit(sprintf("%s%s%s", C_HEAD, DASH_C, RESET))
		n = sorted_keys(nvobj, tbl)
		for (i = 0; i != n; i++) {
			k = tbl[i]
			v = nvobj[k]
			if (substr(v, 1, 1) == "\"") v = decode_json_string(v)
			else if (sub(/^\[[[:space:]]*/, "[", v) != 0) {
				sub(/[[:space:]]*]/, "]", v)
				gsub(/[[:space:]]*,[[:space:]]*/, ", ", v)
			}
			emit(sprintf(" %-30s: %s", k, v))
		}
	}
	pager()
}

function main_loop( \
	\
	choice, idx \
) {
	MTOP = 0
	while (1) {
		print_menu()
		printf "> "
		system("")
		if ((getline choice < "/dev/tty") <= 0) break
		if (choice == "q" || choice == "Q") break
		else if (choice == "r" || choice == "R") { scan_devices(); cache_reset(); MTOP = 0 }
		else if (choice == "n" || choice == "N") { if (MTOP + MROWS < NDEV) MTOP += MROWS }
		else if (choice == "p" || choice == "P") { MTOP -= MROWS; if (MTOP < 0) MTOP = 0 }
		else if (choice == "") continue
		else if (choice ~ /^[0-9]+$/) {
			idx = choice + 0
			if (idx >= 1 && idx <= NDEV)
				print_details(DEV_NAME[idx - 1], DEV_TYPE[idx - 1])
			else {
				print "No such disk."
				pause()
			}
		} else {
			print "Invalid selection."
			pause()
		}
	}
}

BEGIN {
	JSONLEN = -1
	JSONESC["b"] = "\b"
	JSONESC["f"] = "\f"
	JSONESC["n"] = "\n"
	JSONESC["\""] = "\""
	JSONESC["r"] = "\r"
	JSONESC["t"] = "\t"
	JSONESC["/"] = "/"
	JSONESC["\\"] = "\\"

	# 512 assumed, see https://github.com/prometheus-community/smartctl_exporter/issues/122
	BLOCKSIZE = 512
	DASH = "--------------------------------------------------------------------------------"
	BAR = "================================================================================"
	RESET = "\033[0m"
	C_TITLE = "\033[1;33m"
	C_HEAD = "\033[1;36m"
	C_GOOD = "\033[1;36m"
	C_CAUTION = "\033[1;33m"
	C_BAD = "\033[1;31m"
	HEALTH[0] = "Good"
	HEALTH[1] = "Caution"
	HEALTH[2] = "Bad"

	ALTTYPES[0] = "sat"
	ALTTYPES[1] = "auto"
	ALTTYPES[2] = "scsi"
	ALTTYPESLEN = 3

	SIZES[0] = "Byte"
	SIZES[1] = "KB"
	SIZES[2] = "MB"
	SIZES[3] = "GB"
	SIZES[4] = "TB"
	SIZES[5] = "PB"
	SIZES[6] = "EB"
	SIZESLEN = 7

	# https://en.wikipedia.org/wiki/Self-Monitoring,_Analysis_and_Reporting_Technology#Known_ATA_S.M.A.R.T._attributes
	CAUTION[5] = 1
	CAUTION[10] = 1
	CAUTION[187] = 1
	CAUTION[188] = 1
	CAUTION[196] = 1
	CAUTION[197] = 1
	CAUTION[198] = 1
	CAUTION[201] = 1
	INDICATORS[1] = "v!"
	INDICATORS[2] = "^ "
	INDICATORS[3] = "v "
	INDICATORS[5] = "v!"
	INDICATORS[7] = "~ "
	INDICATORS[8] = "^ "
	INDICATORS[10] = "v!"
	INDICATORS[11] = "v "
	INDICATORS[13] = "v "
	INDICATORS[22] = "^ "
	INDICATORS[181] = "v "
	INDICATORS[183] = "v "
	INDICATORS[184] = "v!"
	INDICATORS[187] = "v!"
	INDICATORS[188] = "v!"
	INDICATORS[189] = "v "
	INDICATORS[190] = "~ "
	INDICATORS[191] = "v "
	INDICATORS[192] = "v "
	INDICATORS[193] = "v "
	INDICATORS[194] = "v "
	INDICATORS[195] = "~ "
	INDICATORS[196] = "v!"
	INDICATORS[197] = "v!"
	INDICATORS[198] = "v!"
	INDICATORS[199] = "v "
	INDICATORS[200] = "v "
	INDICATORS[201] = "v!"
	INDICATORS[202] = "v "
	INDICATORS[203] = "v "
	INDICATORS[204] = "v "
	INDICATORS[205] = "v "
	INDICATORS[207] = "v "
	INDICATORS[220] = "v "
	INDICATORS[221] = "v "
	INDICATORS[224] = "v "
	INDICATORS[225] = "v "
	INDICATORS[227] = "v "
	INDICATORS[228] = "v "
	INDICATORS[231] = "^ "
	INDICATORS[232] = "^ "
	INDICATORS[245] = "^ "
	INDICATORS[250] = "v "
	INDICATORS[254] = "v "

	# Failure probability based on https://www.backblaze.com/hard-drive-test-data.html
	SMARTLEN = 256
	FAILID[5] = 1
	FAILID[187] = 1
	FAILID[188] = 1
	FAILID[197] = 1
	FAILID[198] = 1

	# Reallocated Sector Count
	split( \
		"0.0026 0.0748 0.0919 0.1013 0.1079 0.1137 0.1194 0.1235 0.1301 0.1398 0.1453 0.1490 0.1528 0.1566 0.1595 0.1635 " \
		"0.1656 0.1701 0.1718 0.1740 0.1762 0.1787 0.1808 0.1833 0.1858 0.1885 0.1901 0.1915 0.1934 0.1958 0.1975 0.1993 " \
		"0.2014 0.2048 0.2068 0.2088 0.2109 0.2120 0.2137 0.2160 0.2173 0.2214 0.2226 0.2237 0.2262 0.2277 0.2292 0.2304 " \
		"0.2338 0.2369 0.2381 0.2396 0.2411 0.2427 0.2445 0.2462 0.2472 0.2488 0.2496 0.2504 0.2514 0.2525 0.2535 0.2544 " \
		"0.2554 0.2571 0.2583 0.2601 0.2622 0.2631 0.2635 0.2644 0.2659 0.2675 0.2682 0.2692 0.2701 0.2707 0.2712 0.2726 " \
		"0.2745 0.2767 0.2778 0.2784 0.2800 0.2814 0.2834 0.2839 0.2851 0.2877 0.2883 0.2891 0.2900 0.2907 0.2916 0.2934 " \
		"0.2950 0.2969 0.2975 0.2983 0.2999 0.3006 0.3013 0.3021 0.3033 0.3054 0.3066 0.3074 0.3082 0.3094 0.3106 0.3112 " \
		"0.3120 0.3137 0.3141 0.3145 0.3151 0.3159 0.3169 0.3174 0.3181 0.3194 0.3215 0.3219 0.3231 0.3234 0.3237 0.3242 " \
		"0.3255 0.3270 0.3283 0.3286 0.3289 0.3304 0.3315 0.3322 0.3347 0.3361 0.3382 0.3384 0.3395 0.3398 0.3401 0.3405 " \
		"0.3411 0.3431 0.3435 0.3442 0.3447 0.3450 0.3455 0.3464 0.3472 0.3486 0.3497 0.3501 0.3509 0.3517 0.3531 0.3535 " \
		"0.3540 0.3565 0.3569 0.3576 0.3579 0.3584 0.3590 0.3594 0.3599 0.3621 0.3627 0.3642 0.3649 0.3655 0.3658 0.3667 " \
		"0.3683 0.3699 0.3704 0.3707 0.3711 0.3715 0.3718 0.3721 0.3727 0.3740 0.3744 0.3748 0.3753 0.3756 0.3761 0.3766 " \
		"0.3775 0.3794 0.3801 0.3804 0.3813 0.3817 0.3823 0.3831 0.3847 0.3875 0.3881 0.3886 0.3890 0.3893 0.3896 0.3900 " \
		"0.3907 0.3923 0.3925 0.3933 0.3936 0.3961 0.3971 0.3981 0.3989 0.4007 0.4012 0.4018 0.4023 0.4027 0.4041 0.4048 " \
		"0.4056 0.4073 0.4079 0.4086 0.4104 0.4107 0.4109 0.4112 0.4118 0.4133 0.4139 0.4144 0.4146 0.4148 0.4164 0.4165 " \
		"0.4174 0.4191 0.4197 0.4201 0.4204 0.4210 0.4213 0.4216 0.4221 0.4231 0.4235 0.4237 0.4239 0.4241 0.4244 0.4249",
		S5R, " " \
	)

	# Reported Uncorrectable Errors
	split( \
		"0.0039 0.1287 0.1579 0.1776 0.1905 0.2013 0.2226 0.3263 0.3612 0.3869 0.4086 0.4292 0.4559 0.5278 0.5593 0.5847 " \
		"0.6124 0.6345 0.6517 0.6995 0.7308 0.7541 0.7814 0.8122 0.8306 0.8839 0.9100 0.9505 0.9906 1.0254 1.0483 1.1060 " \
		"1.1280 1.1624 1.1895 1.2138 1.2452 1.2864 1.3120 1.3369 1.3705 1.3894 1.4055 1.4218 1.4434 1.4670 1.4834 1.4993 " \
		"1.5174 1.5400 1.5572 1.5689 1.5808 1.6198 1.6346 1.6405 1.6570 1.6618 1.6755 1.6877 1.7100 1.7258 1.7347 1.7814 " \
		"1.7992 1.8126 1.8225 1.8269 1.8341 1.8463 1.8765 1.8850 1.9005 1.9281 1.9398 1.9618 1.9702 1.9905 2.0099 2.0480 " \
		"2.0565 2.0611 2.0709 2.0846 2.0895 2.0958 2.1008 2.1055 2.1097 2.1235 2.1564 2.1737 2.1956 2.1989 2.2015 2.2148 " \
		"2.2355 2.2769 2.2940 2.3045 2.3096 2.3139 2.3344 2.3669 2.3779 2.3941 2.4036 2.4396 2.4473 2.4525 2.4656 2.4762 " \
		"2.4787 2.5672 2.5732 2.5755 2.5794 2.5886 2.6100 2.6144 2.6341 2.6614 2.6679 2.6796 2.6847 2.6872 2.6910 2.6934 " \
		"2.6995 2.7110 2.7179 2.7204 2.7232 2.7282 2.7355 2.7375 2.7422 2.7558 2.7580 2.7643 2.7767 2.7770 2.8016 2.9292 " \
		"2.9294 2.9337 2.9364 2.9409 2.9436 2.9457 2.9466 2.9498 2.9543 2.9570 2.9573 2.9663 2.9708 2.9833 2.9859 2.9895 " \
		"2.9907 2.9932 2.9935 3.0021 3.0035 3.0079 3.0103 3.0126 3.0151 3.0266 3.0288 3.0320 3.0330 3.0343 3.0373 3.0387 " \
		"3.0438 3.0570 3.0579 3.0616 3.0655 3.0728 3.0771 3.0794 3.0799 3.0812 3.1769 3.1805 3.1819 3.1860 3.1869 3.2004 " \
		"3.2016 3.2025 3.2070 3.2129 3.2173 3.2205 3.2254 3.2263 3.2300 3.2413 3.2543 3.2580 3.2595 3.2611 3.2624 3.2787 " \
		"3.2798 3.2809 3.2823 3.2833 3.2834 3.2853 3.2866 3.3332 3.3580 3.3595 3.3625 3.3631 3.3667 3.3702 3.3737 3.3742 " \
		"3.3747 3.3769 3.3775 3.3791 3.3809 3.3813 3.3814 3.3822 3.3827 3.3828 3.3833 3.3833 3.3843 3.3882 3.3963 3.4047 " \
		"3.4057 3.4213 3.4218 3.4230 3.4231 3.4240 3.4262 3.4283 3.4283 3.4288 3.4293 3.4302 3.4317 3.4478 3.4486 3.4520",
		S187R, " " \
	)

	# Command Timeout
	split( \
		"0.0025 0.0129 0.0182 0.0215 0.0236 0.0257 0.0279 0.0308 0.0341 0.0382 0.0430 0.0491 0.0565 0.0658 0.0770 0.0906 " \
		"0.1037 0.1197 0.1355 0.1525 0.1686 0.1864 0.2011 0.2157 0.2281 0.2404 0.2505 0.2591 0.2676 0.2766 0.2827 0.2913 " \
		"0.2999 0.3100 0.3185 0.3298 0.3361 0.3446 0.3506 0.3665 0.3699 0.3820 0.3890 0.4059 0.4108 0.4255 0.4290 0.4424 " \
		"0.4473 0.4617 0.4667 0.4770 0.4829 0.4977 0.4997 0.5102 0.5137 0.5283 0.5316 0.5428 0.5480 0.5597 0.5634 0.5791 " \
		"0.5826 0.5929 0.5945 0.6025 0.6102 0.6175 0.6245 0.6313 0.6421 0.6468 0.6497 0.6557 0.6570 0.6647 0.6698 0.6769 " \
		"0.6849 0.6884 0.6925 0.7025 0.7073 0.7161 0.7223 0.7256 0.7280 0.7411 0.7445 0.7530 0.7628 0.7755 0.7900 0.8006 " \
		"0.8050 0.8098 0.8132 0.8192 0.8230 0.8293 0.8356 0.8440 0.8491 0.8672 0.8766 0.8907 0.8934 0.8992 0.9062 0.9111 " \
		"0.9209 0.9290 0.9329 0.9378 0.9385 0.9402 0.9427 0.9448 0.9459 0.9568 0.9626 0.9628 0.9730 0.9765 0.9797 0.9825 " \
		"0.9873 0.9902 0.9926 0.9991 1.0031 1.0044 1.0062 1.0120 1.0148 1.0188 1.0218 1.0231 1.0249 1.0277 1.0335 1.0355 " \
		"1.0417 1.0467 1.0474 1.0510 1.0529 1.0532 1.0562 1.0610 1.0702 1.0708 1.0800 1.0804 1.0845 1.1120 1.1191 1.1225 " \
		"1.1264 1.1265 1.1335 1.1347 1.1479 1.1479 1.1519 1.1545 1.1645 1.1646 1.1647 1.1649 1.1678 1.1713 1.1723 1.1733 " \
		"1.1736 1.1736 1.1738 1.1739 1.1739 1.1741 1.1741 1.1746 1.1746 1.1748 1.1750 1.1760 1.1794 1.1854 1.1908 1.1912 " \
		"1.1912 1.1971 1.2033 1.2033 1.2120 1.2166 1.2185 1.2185 1.2189 1.2211 1.2226 1.2234 1.2320 1.2345 1.2345 1.2347 " \
		"1.2350 1.2350 1.2407 1.2408 1.2408 1.2408 1.2409 1.2460 1.2518 1.2519 1.2519 1.2519 1.2520 1.2520 1.2521 1.2521 " \
		"1.2521 1.2593 1.2745 1.2760 1.2772 1.2831 1.2833 1.2890 1.2906 1.3166 1.3201 1.3202 1.3202 1.3202 1.3204 1.3204 " \
		"1.3314 1.3422 1.3423 1.3441 1.3491 1.3583 1.3602 1.3606 1.3636 1.3650 1.3661 1.3703 1.3708 1.3716 1.3730 1.3731",
		S188R, " " \
	)

	# Current Pending Sector Count
	split( \
		"0.0028 0.2972 0.3883 0.4363 0.4644 0.4813 0.4948 0.5051 0.5499 0.8535 0.8678 0.8767 0.8882 0.8933 0.9012 0.9076 " \
		"0.9368 1.1946 1.2000 1.2110 1.2177 1.2305 1.2385 1.2447 1.2699 1.4713 1.4771 1.4802 1.4887 1.5292 1.5384 1.5442 " \
		"1.5645 1.7700 1.7755 1.7778 1.7899 1.7912 1.7991 1.7998 1.8090 1.9974 1.9992 2.0088 2.0132 2.0146 2.0161 2.0171 " \
		"2.0273 2.1845 2.1866 2.1877 2.1900 2.1922 2.1944 2.1974 2.2091 2.3432 2.3459 2.3463 2.3468 2.3496 2.3503 2.3533 " \
		"2.3593 2.4604 2.4606 2.4609 2.4612 2.4620 2.4626 2.4638 2.4689 2.5575 2.5581 2.5586 2.5586 2.5588 2.5602 2.5602 " \
		"2.5648 2.6769 2.6769 2.6769 2.6794 2.6805 2.6811 2.6814 2.6862 2.7742 2.7755 2.7771 2.7780 2.7790 2.7797 2.7807 " \
		"2.7871 2.9466 2.9478 2.9492 2.9612 2.9618 2.9624 2.9628 2.9669 3.1467 3.1481 3.1494 3.1499 3.1504 3.1507 3.1509 " \
		"3.1532 3.2675 3.2681 3.2703 3.2712 3.2714 3.2726 3.2726 3.2743 3.3376 3.3379 3.3382 3.3397 3.3403 3.3410 3.3410 " \
		"3.3429 3.4052 3.4052 3.4052 3.4052 3.4052 3.4053 3.4053 3.4075 3.4616 3.4616 3.4616 3.4616 3.4616 3.4616 3.4620 " \
		"3.4634 3.4975 3.4975 3.4975 3.4975 3.4979 3.4979 3.4979 3.4998 3.5489 3.5489 3.5489 3.5489 3.5489 3.5493 3.5497 " \
		"3.5512 3.5827 3.5828 3.5828 3.5828 3.5828 3.5828 3.5828 3.5844 3.6251 3.6251 3.6251 3.6267 3.6267 3.6271 3.6271 " \
		"3.6279 3.6562 3.6562 3.6563 3.7206 3.7242 3.7332 3.7332 3.7346 3.7548 3.7548 3.7553 3.7576 3.7581 3.7586 3.7587 " \
		"3.7600 3.7773 3.7812 3.7836 3.7841 3.7842 3.7851 3.7856 3.7876 3.8890 3.8890 3.8890 3.8890 3.8890 3.8890 3.8890 " \
		"3.8897 3.9111 3.9114 3.9114 3.9114 3.9114 3.9114 3.9114 3.9126 3.9440 3.9440 3.9440 3.9440 3.9440 3.9498 3.9498 " \
		"3.9509 3.9783 3.9783 3.9784 3.9784 3.9784 3.9784 4.0012 4.0019 4.0406 4.0413 4.0413 4.0413 4.0413 4.0414 4.0414 " \
		"4.0421 4.0552 4.0552 4.0558 4.0558 4.0558 4.0558 4.0558 4.0563 4.0753 4.0753 4.0760 4.1131 4.1131 4.1131 4.1131",
		S197R, " " \
	)

	# Offline Uncorrectable
	split( \
		"0.0030 0.5479 0.5807 0.5949 0.6046 0.6086 0.6139 0.6224 0.6639 1.0308 1.0329 1.0364 1.0371 1.0387 1.0399 1.0421 " \
		"1.0675 1.3730 1.3733 1.3741 1.3741 1.3752 1.3794 1.3800 1.3985 1.6291 1.6303 1.6309 1.6352 1.6384 1.6448 1.6464 " \
		"1.6645 1.8949 1.8951 1.8962 1.9073 1.9073 1.9152 1.9161 1.9240 2.1308 2.1315 2.1328 2.1328 2.1328 2.1328 2.1329 " \
		"2.1439 2.3203 2.3205 2.3205 2.3205 2.3205 2.3205 2.3205 2.3265 2.4729 2.4729 2.4729 2.4729 2.4729 2.4729 2.4729 " \
		"2.4778 2.5900 2.5900 2.5901 2.5901 2.5901 2.5901 2.5901 2.5949 2.6964 2.6965 2.6965 2.6965 2.6965 2.6965 2.6965 " \
		"2.7010 2.8328 2.8328 2.8328 2.8329 2.8329 2.8329 2.8329 2.8366 2.9405 2.9405 2.9405 2.9405 2.9405 2.9405 2.9405 " \
		"2.9442 3.1344 3.1344 3.1346 3.1463 3.1463 3.1463 3.1463 3.1493 3.3076 3.3076 3.3076 3.3076 3.3076 3.3077 3.3077 " \
		"3.3097 3.4456 3.4456 3.4456 3.4456 3.4456 3.4456 3.4456 3.4473 3.5236 3.5236 3.5236 3.5236 3.5236 3.5236 3.5236 " \
		"3.5249 3.6004 3.6004 3.6004 3.6004 3.6004 3.6004 3.6004 3.6026 3.6684 3.6684 3.6684 3.6684 3.6684 3.6684 3.6684 " \
		"3.6697 3.7121 3.7121 3.7121 3.7121 3.7121 3.7121 3.7121 3.7136 3.7744 3.7744 3.7744 3.7744 3.7744 3.7745 3.7745 " \
		"3.7756 3.8151 3.8151 3.8151 3.8151 3.8151 3.8151 3.8151 3.8163 3.8673 3.8673 3.8673 3.8673 3.8673 3.8673 3.8673 " \
		"3.8680 3.9044 3.9044 3.9044 3.9044 3.9044 3.9044 3.9044 3.9056 3.9297 3.9297 3.9297 3.9297 3.9297 3.9297 3.9297 " \
		"3.9305 3.9494 3.9494 3.9494 3.9494 3.9494 3.9494 3.9494 3.9514 4.0725 4.0725 4.0725 4.0725 4.0725 4.0725 4.0725 " \
		"4.0731 4.0990 4.0993 4.0993 4.0993 4.0993 4.0993 4.0993 4.1004 4.1385 4.1385 4.1385 4.1386 4.1386 4.1387 4.1387 " \
		"4.1398 4.1732 4.2284 4.2284 4.2284 4.2284 4.2284 4.2284 4.2290 4.2781 4.2781 4.2963 4.2963 4.2963 4.2963 4.2963 " \
		"4.2971 4.3141 4.3141 4.3141 4.3141 4.3141 4.3141 4.3141 4.3146 4.3393 4.3393 4.3393 4.3393 4.3393 4.3393 4.3393",
		S198R, " " \
	)

	if (system("command -v smartctl >/dev/null 2>&1") != 0)
		die("smartctl not found. Install smartmontools.")

	if (run("id -u") + 0 != 0)
		die("root privileges are required to read S.M.A.R.T data. Use sudo.")

	scan_devices()
	if (NDEV == 0)
		die("No S.M.A.R.T readable devices found.")

	enter_tui()
	main_loop()
	leave_tui()
	exit 0
}
