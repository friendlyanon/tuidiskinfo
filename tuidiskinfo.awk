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
	out, esc \
) {
	if (s !~ /^"./ || substr(s, length(s), 1) != "\"")
		die("invalid json string " s)
	s = substr(s, 2, length(s)-2)
	esc["b"] = "\b"; esc["f"] = "\f"; esc["n"] = "\n"; esc["\""] = "\""
	esc["r"] = "\r"; esc["t"] = "\t"; esc["/"] = "/" ; esc["\\"] = "\\"
	while (match(s, /\\/)) {
		if (!(substr(s, RSTART+1, 1) in esc))
			die("unknown json escape " substr(s, RSTART, 2))
		out = out substr(s, 1, RSTART-1) esc[substr(s, RSTART+1, 1)]
		s = substr(s, RSTART+2)
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
	scan, devs, n, i, name \
) {
	NDEV = 0
	scan = run("smartctl --scan -j 2>/dev/null")
	if (substr(gv(scan, "devices", devs), 1, 1) != "[") return
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

function attr_health(id, value, thresh, rawv) {
	if (thresh != 0 && value < thresh) return 2
	if (rawv != 0 && id in CAUTION) return 1
	return 0
}

function device_health( \
	json,
	tbl, n, i, hmax, t, tn, temp, st, status, nv, nvw \
) {
	gv(json, "ata_smart_attributes.table", tbl)
	n = JSONLEN
	hmax = 0
	for (i = 0; i < n; i++) {
		hmax = max(hmax, attr_health(num(tbl[i], "id"), num(tbl[i], "value"), \
			num(tbl[i], "thresh"), num(tbl[i], "raw.value")))
	}
	t = gv(json, "temperature.current")
	if (t == "") temp = 0
	else {
		tn = t + 0
		if (tn < 50) temp = 0
		else if (tn < 55) temp = 1
		else temp = 2
	}
	st = gv(json, "smart_status.passed")
	status = st == "false" ? 2 : 0
	nv = gv(json, "nvme_smart_health_information_log.critical_warning")
	nvw = nv != "" && nv != "0" ? 1 : 0
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
	printf " %-3s %-14s %-30s %6s  %s\n", "No", "Device", "Model", "Temp", "Health"
	printf "%s\n%s", DASH_C, RESET
}

function cache_device( \
	i,
	json, n, t \
) {
	if (i in CACHED) return
	json = smart_json(DEV_NAME[i], DEV_TYPE[i])
	n = str(json, "model_name", "")
	CACHE_MODEL[i] = n == "" ? str(json, "scsi_model_name", "Unknown") : n
	t = gv(json, "temperature.current")
	CACHE_TEMP[i] = t == "" || t == "0" ? "--" : t " C"
	CACHE_HEALTH[i] = device_health(json)
	CACHED[i] = 1
}

function cache_reset() {
	split("", CACHED)
}

function print_menu( \
	\
	i, rows, shown, pages, page \
) {
	term_size()
	cls()
	print_header()
	system("")
	rows = LINES - 7
	if (rows < 1) rows = 1
	MROWS = rows
	if (MTOP < 0 || MTOP >= NDEV) MTOP = 0
	shown = 0
	for (i = MTOP; i < NDEV && shown < rows; i++) {
		cache_device(i)
		printf " %2d) %-14s %-30.30s %6s  %s\n", \
			i + 1, DEV_NAME[i], CACHE_MODEL[i], CACHE_TEMP[i], color_health(CACHE_HEALTH[i])
		system("")
		shown++
	}
	print DASH_C
	pages = int((NDEV + rows - 1) / rows)
	page = int(MTOP / rows) + 1
	printf "Page %d/%d  [number] details  [n]ext [p]rev [r]efresh [q]uit\n", \
		page, pages
}

function emit_banner(name, model, health, status, tdisp, firmware, serial, cap, rotation, poh, cycles, hr, hw, mode) {
	emit(sprintf("%s%s%s", C_HEAD, BAR_C, RESET))
	emit(sprintf("%s %s  -  %s%s", C_HEAD, name, model, RESET))
	emit(sprintf("%s%s%s", C_HEAD, BAR_C, RESET))
	emit(sprintf(" %-16s: %s", "Health", color_health(health)))
	emit(sprintf(" %-16s: %s", "SMART Status", status))
	emit(sprintf(" %-16s: %s", "Temperature", tdisp))
	emit(sprintf(" %-16s: %s", "Firmware", firmware))
	emit(sprintf(" %-16s: %s", "Serial", serial))
	emit(sprintf(" %-16s: %s", "Capacity", human_size(cap)))
	emit(sprintf(" %-16s: %s", "Transfer Mode", mode))
	emit(sprintf(" %-16s: %s", "Rotation Rate", rotation))
	emit(sprintf(" %-16s: %s", "Power On Hours", poh))
	emit(sprintf(" %-16s: %s", "Power On Count", cycles))
	emit(sprintf(" %-16s: %s", "Host Reads", hr))
	emit(sprintf(" %-16s: %s", "Host Writes", hw))
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
	json, model, firmware, serial, cap, rr, rotation, poh, cycles, t, tdisp, st,
	status, health, hr, hw, dur, duw, x, tbl, n, i, id, val, thr, rawv, raw,
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
	tdisp = t == "" || t == "0" ? "--" : t " C"
	st = gv(json, "smart_status.passed")
	status = st == "true" ? "PASSED" : st == "false" ? "FAILED" : "--"
	health = device_health(json)

	buf_reset()
	gv(json, "ata_smart_attributes.table", tbl)
	n = JSONLEN
	if (n > 0) {
		x = ata_attr_raw(tbl, n, 242); hr = x == "" ? "--" : human_size(x * BLOCKSIZE)
		x = ata_attr_raw(tbl, n, 241); hw = x == "" ? "--" : human_size(x * BLOCKSIZE)
		emit_banner(name, model, health, status, tdisp, firmware, serial, cap, rotation, poh, cycles, hr, hw, get_sata_mode(name))
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
			emit(sprintf(" %s %3d %-25.25s %4d %4d %4d  %s %s", \
				color_health(HEALTH[attr_health(id, val, thr, rawv)]), \
				id, str(tbl[i], "name", ""), val, num(tbl[i], "worst"), thr, \
				id in INDICATORS ? INDICATORS[id] : "  ", raw))
		}
	} else if (gv(json, "nvme_smart_health_information_log", nvobj) != "") {
		dur = nvobj["data_units_read"]; hr = dur == "" ? "--" : human_size(dur * 1000 * BLOCKSIZE)
		duw = nvobj["data_units_written"]; hw = duw == "" ? "--" : human_size(duw * 1000 * BLOCKSIZE)
		emit_banner(name, model, health, status, tdisp, firmware, serial, cap, rotation, poh, cycles, hr, hw, get_nvme_mode(name))
		emit(sprintf("%s%s%s", C_HEAD, DASH_C, RESET))
		emit(sprintf("%s NVMe Health Information Log%s", C_HEAD, RESET))
		emit(sprintf("%s%s%s", C_HEAD, DASH_C, RESET))
		n = sorted_keys(nvobj, tbl)
		for (i = 0; i != n; i++) {
			k = tbl[i]
			v = nvobj[k]
			if (substr(v, 1, 1) == "\"") v = decode_json_string(v)
			else if (substr(v, 1, 1) == "[") {
				gsub(/\[[[:space:]]*/, "[", v)
				gsub(/[[:space:]]*]/, "]", v)
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
