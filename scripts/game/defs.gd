class_name Defs
## Every number and Persian name in the game lives here, so balance and wording are easy to edit.

# ---------------- map ----------------
const GRID := 80            # cells per side
const CELL := 2.0           # metres per cell
const HALF := GRID * CELL * 0.5
const WATER_LEVEL := -0.35

const IRAN := 0
const TURAN := 1
const DIVS := 2

const FACTIONS := [
	{"n": "ایران", "adj": "ایرانی"},
	{"n": "توران", "adj": "تورانی"},
	{"n": "دیوان", "adj": "دیو"},
]
static var faction_color: Array[Color] = [Color("#2f63d0"), Color("#c23a30"), Color("#6b4f80")]
static var faction_dark: Array[Color] = [Color("#16357f"), Color("#5e1612"), Color("#2b1d38")]

## Castle positions in cells.
const KEEP_CELL := [Vector2i(16, 62), Vector2i(62, 16)]
const VILLAGE_CELLS := [Vector2i(22, 30), Vector2i(40, 40), Vector2i(57, 49)]

# ---------------- resources ----------------
const RES_ORDER := ["wood", "stone", "food", "gold"]
const RES_NAMES := {"wood": "چوب", "stone": "سنگ", "food": "غذا", "gold": "طلا"}
const START_RES := {"wood": 120, "stone": 60, "food": 80, "gold": 60}

# ---------------- buildings ----------------
## size: footprint in cells. pop: workers it needs. need: placement rule.
const BUILDINGS := {
	"keep": {"n": "دژ", "size": 4, "hp": 2400, "cost": {}, "pop": 0,
		"desc": "دل قلعه. اگر ویران شود، شکست خورده‌ای. ارتقا جان و جمعیت را بیشتر می‌کند."},
	"house": {"n": "خانه", "size": 2, "hp": 300, "cost": {"wood": 25}, "pop": 0,
		"desc": "جای زندگی ۵ نفر دیگر.", "pop_cap": 5},
	"woodcutter": {"n": "هیزم‌شکن", "size": 2, "hp": 300, "cost": {"wood": 15}, "pop": 1,
		"desc": "از درختان نزدیک چوب می‌آورد.", "res": "wood", "amt": 6, "every": 10.0, "need": "trees"},
	"quarry": {"n": "معدن سنگ", "size": 2, "hp": 400, "cost": {"wood": 30}, "pop": 2,
		"desc": "باید کنار صخره‌های خاکستری ساخته شود.", "res": "stone", "amt": 6, "every": 12.0, "need": "rocks"},
	"farm": {"n": "مزرعه‌ی گندم", "size": 3, "hp": 250, "cost": {"wood": 20}, "pop": 1,
		"desc": "غذای مردم و سپاه را فراهم می‌کند.", "res": "food", "amt": 8, "every": 12.0},
	"barracks": {"n": "سربازخانه", "size": 3, "hp": 900, "cost": {"wood": 50, "stone": 30}, "pop": 0,
		"desc": "سرباز تربیت می‌کند."},
	"tower": {"n": "برج تیرانداز", "size": 1, "hp": 700, "cost": {"stone": 30}, "pop": 0,
		"desc": "به دشمنان نزدیک تیر می‌بارد.", "range": 18.0, "dmg": 9, "cd": 1.6},
	"wall": {"n": "دیوار سنگی", "size": 1, "hp": 600, "cost": {"stone": 5}, "pop": 0,
		"desc": "با دو ضربه روی زمین، از نقطه‌ی اول تا دوم دیوار بکش."},
	"gate": {"n": "دروازه", "size": 1, "hp": 800, "cost": {"stone": 20, "wood": 10}, "pop": 0,
		"desc": "سپاه خودی از آن می‌گذرد و دشمن نه."},
	"village": {"n": "روستا", "size": 3, "hp": 99999, "cost": {}, "pop": 0,
		"desc": "سپاهت را کنارش ببر تا تصرف شود. سرزمین و درآمدت را بیشتر می‌کند."},
}
## Build bar order.
const BUILD_MENU := ["house", "farm", "woodcutter", "quarry", "barracks", "tower", "wall", "gate"]

const KEEP_LEVELS := [
	{"hp": 2400, "pop_cap": 10, "radius": 26.0, "cost": {}},
	{"hp": 3600, "pop_cap": 16, "radius": 32.0, "cost": {"wood": 80, "stone": 100, "gold": 60}},
	{"hp": 5000, "pop_cap": 24, "radius": 38.0, "cost": {"stone": 180, "gold": 140}},
]
const VILLAGE_RADIUS := 18.0
const KEEP_ARROW := {"range": 20.0, "dmg": 10, "cd": 1.4}

# ---------------- units ----------------
## range in metres, speed in m/s, cd = seconds between hits.
const UNITS := {
	"spear": {"n": "نیزه‌دار", "hp": 70, "dmg": 9, "range": 1.8, "speed": 4.2, "cd": 1.0, "armor": 0.15,
		"cost": {"food": 10, "wood": 10, "gold": 5}, "time": 4.0,
		"desc": "پیاده‌ی پایدار. در برابر سواره دو برابر می‌زند."},
	"archer": {"n": "کماندار", "hp": 45, "dmg": 7, "range": 15.0, "speed": 4.2, "cd": 1.5, "armor": 0.0,
		"cost": {"food": 10, "wood": 20, "gold": 10}, "time": 5.0,
		"desc": "از دور تیر می‌اندازد. بالای دیوار یا پشت نیزه‌داران نگهش دار."},
	"cav": {"n": "اسوار", "hp": 110, "dmg": 13, "range": 2.0, "speed": 7.5, "cd": 1.1, "armor": 0.1,
		"cost": {"food": 20, "gold": 30}, "time": 7.0,
		"desc": "سواره‌ی تندرو. کمانداران را آسان می‌شکند."},
	"immortal": {"n": "جاویدان", "hp": 160, "dmg": 15, "range": 1.9, "speed": 3.8, "cd": 1.1, "armor": 0.35,
		"cost": {"food": 20, "stone": 10, "gold": 45}, "time": 8.0, "keep_level": 2,
		"desc": "گارد زره‌پوش شاهنشاهی. به دژ سطح ۲ نیاز دارد."},
	"hero": {"n": "پهلوان", "hp": 520, "dmg": 34, "range": 2.2, "speed": 5.6, "cd": 1.0, "armor": 0.3,
		"cost": {}, "time": 0.0, "desc": ""},
	"div": {"n": "دیو", "hp": 300, "dmg": 17, "range": 2.6, "speed": 3.2, "cd": 1.6, "armor": 0.2,
		"cost": {}, "time": 0.0, "desc": "دیو مازندران. روستا را در بند دارد. کشتنش ۴۰ طلا پاداش دارد."},
}
const TRAIN_MENU := ["spear", "archer", "cav", "immortal"]
const HEROES := [
	{"n": "رستم", "desc": "جهان‌پهلوان، با گرز گاوسر. اگر بیفتد، سیمرغ پس از ۴۵ ثانیه او را به دژ بازمی‌گرداند."},
	{"n": "افراسیاب", "desc": "شاه توران. اگر بیفتد، پس از مدتی از غار پنهانش بازمی‌گردد."},
]
const HERO_RESPAWN := 45.0

# ---------------- economy timing ----------------
const TAX_EVERY := 4.0          # keep gives gold
const TAX_GOLD := 2
const VILLAGE_EVERY := 6.0
const VILLAGE_INCOME := {"gold": 3, "food": 3}
const FOOD_EVERY := 10.0        # everyone eats
const FOOD_PER_10 := 0.5        # food per person per FOOD_EVERY seconds
const CAPTURE_TIME := 6.0

# ---------------- difficulty ----------------
const DIFFICULTY := {
	"easy": {"n": "آسان", "first": 210.0, "every": 200.0, "base": 3, "grow": 1.0, "income": 0.8},
	"normal": {"n": "معمولی", "first": 160.0, "every": 160.0, "base": 4, "grow": 1.6, "income": 1.0},
	"hard": {"n": "سخت", "first": 110.0, "every": 120.0, "base": 6, "grow": 2.2, "income": 1.35},
}


static func fa(n) -> String:
	const DIGITS := "۰۱۲۳۴۵۶۷۸۹"
	var s := str(n)
	var out := ""
	for ch in s:
		if ch >= "0" and ch <= "9":
			out += DIGITS[ch.unicode_at(0) - 48]
		elif ch == "-":
			out += "−"
		else:
			out += ch
	return out


static func fa_time(sec: float) -> String:
	var s := maxi(0, int(sec))
	return fa("%d:%02d" % [s / 60, s % 60])


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in RES_ORDER:
		if cost.has(k):
			parts.append("%s %s" % [fa(cost[k]), RES_NAMES[k]])
	return "، ".join(parts) if parts.size() > 0 else "رایگان"


static func unit_name(type: String, owner: int) -> String:
	if type == "hero":
		return HEROES[owner].n if owner < 2 else "پهلوان"
	return UNITS[type].n
