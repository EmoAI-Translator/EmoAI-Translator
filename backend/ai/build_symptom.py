import json
import re
from typing import Dict, List, Tuple

# --------------------------------------------------
# 1) Scenario-based symptom pools (KO canonical)
# --------------------------------------------------
SYMPTOM_SCENARIOS: Dict[str, List[Tuple[str, str, str, str]]] = {
    "respiratory": [
        ("기침", "cough", "咳嗽", "咳"),
        ("마른기침", "dry cough", "干咳", "乾いた咳"),
        ("가래", "sputum", "痰", "痰"),
        ("피 섞인 가래", "blood-tinged sputum", "痰中带血", "血痰"),
        ("인후통", "sore throat", "咽喉痛", "喉の痛み"),
        ("호흡곤란", "shortness of breath", "呼吸困难", "呼吸困難"),
        ("숨참", "breathlessness", "气短", "息切れ"),
        ("쌕쌕거림", "wheezing", "喘鸣", "喘鳴"),
        ("흉부 답답함", "chest tightness", "胸闷", "胸の圧迫感"),
        ("콧물", "runny nose", "流鼻涕", "鼻水"),
        ("코막힘", "nasal congestion", "鼻塞", "鼻づまり"),
        ("재채기", "sneezing", "打喷嚏", "くしゃみ"),
        ("목쉼", "hoarseness", "声音嘶哑", "声がかれる"),
        (
            "가슴 통증(기침 시)",
            "chest pain when coughing",
            "咳嗽时胸痛",
            "咳で胸が痛い",
        ),
        ("숨 쌕쌕", "wheezy breathing", "喘息样喘鸣", "ゼーゼーする"),
    ],
    "gastrointestinal": [
        ("복통", "abdominal pain", "腹痛", "腹痛"),
        ("속쓰림", "heartburn", "烧心", "胸やけ"),
        ("구토", "vomiting", "呕吐", "嘔吐"),
        ("메스꺼움", "nausea", "恶心", "吐き気"),
        ("설사", "diarrhea", "腹泻", "下痢"),
        ("변비", "constipation", "便秘", "便秘"),
        ("복부 팽만", "abdominal bloating", "腹胀", "腹部膨満"),
        ("식욕부진", "loss of appetite", "食欲不振", "食欲不振"),
        ("삼킴 곤란", "difficulty swallowing", "吞咽困难", "嚥下困難"),
        ("혈변", "bloody stool", "便血", "血便"),
        ("검은변", "black stool", "黑便", "黒色便"),
        ("설사(물설사)", "watery diarrhea", "水样腹泻", "水様便"),
        ("복부 경련", "abdominal cramps", "腹部痉挛", "腹部けいれん"),
        ("트림", "belching", "打嗝", "げっぷ"),
        ("가스참", "gas/bloating", "胀气", "ガスがたまる"),
    ],
    "neurological": [
        ("두통", "headache", "头痛", "頭痛"),
        ("어지럼", "dizziness", "头晕", "めまい"),
        ("현기증", "lightheadedness", "眩晕", "ふらつき"),
        ("감각 저하", "numbness", "麻木", "しびれ"),
        ("저림", "tingling", "刺痛感", "ピリピリする"),
        ("경련", "seizure", "抽搐", "けいれん"),
        ("혼동", "confusion", "意识混乱", "混乱"),
        ("말 어눌함", "slurred speech", "言语含糊", "ろれつが回らない"),
        ("시야 흐림", "blurred vision", "视力模糊", "視界がぼやける"),
        ("기억력 저하", "memory loss", "记忆力下降", "記憶力低下"),
        ("균형감각 저하", "loss of balance", "平衡感差", "ふらつく"),
        ("손발 힘 빠짐", "weakness in limbs", "四肢无力", "手足に力が入らない"),
        ("감각 이상", "sensory changes", "感觉异常", "感覚異常"),
        ("빛에 민감", "sensitivity to light", "畏光", "光に敏感"),
        ("소리에 민감", "sensitivity to sound", "对声音敏感", "音に敏感"),
    ],
    "chest_emergency": [
        ("흉통", "chest pain", "胸痛", "胸痛"),
        ("가슴 압박감", "chest pressure", "胸部压迫感", "胸の圧迫感"),
        ("심계항진", "palpitations", "心悸", "動悸"),
        ("호흡 시 통증", "pain on breathing", "呼吸时疼痛", "呼吸時の痛み"),
        ("식은땀", "cold sweat", "冷汗", "冷や汗"),
        ("청색증", "cyanosis", "发绀", "チアノーゼ"),
        ("실신", "syncope", "晕厥", "失神"),
        ("가슴 두근거림", "heart pounding", "心跳很快", "心臓がドキドキする"),
        ("극심한 흉부 통증", "severe chest pain", "剧烈胸痛", "激しい胸痛"),
        ("숨이 막힘", "feeling unable to breathe", "喘不过气", "息ができない"),
        (
            "턱/왼팔로 퍼지는 통증",
            "radiating pain to jaw/left arm",
            "放射痛至下颌/左臂",
            "顎や左腕への放散痛",
        ),
        (
            "갑작스러운 호흡곤란",
            "sudden shortness of breath",
            "突发呼吸困难",
            "突然の呼吸困難",
        ),
        (
            "가슴이 쥐어짜는 느낌",
            "squeezing chest sensation",
            "胸口被挤压感",
            "締めつけられる感じ",
        ),
        ("심한 불안", "severe anxiety", "强烈不安", "強い不安"),
        ("극심한 무기력", "extreme weakness", "极度无力", "極度の脱力"),
    ],
    "skin_allergy": [
        ("발진", "rash", "皮疹", "発疹"),
        ("가려움", "itching", "瘙痒", "かゆみ"),
        ("두드러기", "hives", "荨麻疹", "蕁麻疹"),
        ("부종", "swelling", "肿胀", "腫れ"),
        ("홍반", "erythema", "红斑", "紅斑"),
        ("피부 벗겨짐", "skin peeling", "脱皮", "皮むけ"),
        ("물집", "blister", "水疱", "水疱"),
        ("피부 통증", "skin pain", "皮肤疼痛", "皮膚の痛み"),
        ("얼굴 부기", "facial swelling", "面部肿胀", "顔の腫れ"),
        ("입술 부종", "lip swelling", "嘴唇肿胀", "唇の腫れ"),
        ("눈꺼풀 부종", "eyelid swelling", "眼睑肿胀", "まぶたの腫れ"),
        ("따가움", "stinging sensation", "刺痛", "ヒリヒリする"),
        ("피부 열감", "warmth on skin", "皮肤发热", "熱感"),
        ("피부 건조", "dry skin", "皮肤干燥", "乾燥肌"),
        ("붉어짐", "redness", "发红", "赤み"),
    ],
    "musculoskeletal": [
        ("요통", "lower back pain", "腰痛", "腰痛"),
        ("관절통", "joint pain", "关节痛", "関節痛"),
        ("근육통", "muscle pain", "肌肉痛", "筋肉痛"),
        ("경직", "stiffness", "僵硬", "こわばり"),
        ("압통", "tenderness", "压痛", "圧痛"),
        ("부기(관절)", "joint swelling", "关节肿胀", "関節の腫れ"),
        ("운동 제한", "limited movement", "活动受限", "可動域制限"),
        ("통증 악화", "worsening pain", "疼痛加重", "痛みの悪化"),
        ("쥐남", "muscle cramp", "抽筋", "こむら返り"),
        ("근력 약화", "muscle weakness", "肌力下降", "筋力低下"),
        ("목 통증", "neck pain", "颈部疼痛", "首の痛み"),
        ("어깨 통증", "shoulder pain", "肩痛", "肩の痛み"),
        ("무릎 통증", "knee pain", "膝痛", "膝の痛み"),
        ("손목 통증", "wrist pain", "手腕痛", "手首の痛み"),
        ("발목 통증", "ankle pain", "踝关节痛", "足首の痛み"),
    ],
    "general": [
        ("발열", "fever", "发热", "発熱"),
        ("오한", "chills", "寒战", "悪寒"),
        ("피로", "fatigue", "疲劳", "疲労"),
        ("전신 쇠약", "general weakness", "全身乏力", "全身のだるさ"),
        ("식은땀(야간)", "night sweats", "盗汗", "寝汗"),
        ("체중 감소", "weight loss", "体重下降", "体重減少"),
        ("체중 증가", "weight gain", "体重增加", "体重増加"),
        ("불면", "insomnia", "失眠", "不眠"),
        ("식욕 증가", "increased appetite", "食欲增加", "食欲増加"),
        ("탈수감", "dehydration", "脱水", "脱水"),
        ("목마름", "thirst", "口渴", "のどの渇き"),
        ("통증", "pain", "疼痛", "痛み"),
        ("가슴 답답함(전신)", "tightness", "闷", "圧迫感"),
        ("근육 약화(전신)", "weakness", "无力", "脱力"),
        ("몸살", "body aches", "全身酸痛", "体の痛み"),
    ],
}

# --------------------------------------------------
# 2) Alias rules & curated medical synonyms (safe + practical)
# --------------------------------------------------

CURATED_ALIASES = {
    # respiratory
    "호흡곤란": {
        "en": [
            "dyspnea",
            "difficulty breathing",
            "trouble breathing",
            "can't catch my breath",
        ],
        "ko": ["숨이 차요", "숨쉬기 힘들어요", "호흡이 힘들어요", "숨이 가빠요"],
        "zh": ["气促", "喘不过气", "呼吸不顺", "呼吸费力"],
        "ja": ["息が苦しい", "呼吸が苦しい", "息がしづらい", "息切れ"],
    },
    "숨참": {
        "en": ["breathlessness", "short of breath"],
        "ko": ["숨이 차요", "숨 가빠요", "헐떡거려요"],
        "zh": ["气短", "喘不过气"],
        "ja": ["息切れ", "息が上がる"],
    },
    "쌕쌕거림": {
        "en": ["wheezing", "wheeze", "whistling sound when breathing"],
        "ko": ["숨쉴 때 쌕쌕거려요", "숨소리가 휘파람 같아요", "쌕쌕 소리가 나요"],
        "zh": ["喘鸣", "呼吸有哨音"],
        "ja": ["喘鳴", "ゼーゼーする", "ヒューヒューする"],
    },
    "가래": {
        "en": ["phlegm", "mucus", "sputum"],
        "ko": ["가래가 나와요", "가래가 끓어요", "가래가 많아요"],
        "zh": ["痰", "有痰", "痰很多"],
        "ja": ["痰が出る", "痰が絡む", "痰が多い"],
    },
    "인후통": {
        "en": ["throat pain", "sore throat"],
        "ko": ["목이 아파요", "목이 따가워요", "삼킬 때 목이 아파요"],
        "zh": ["喉咙痛", "咽喉痛"],
        "ja": ["喉が痛い", "のどの痛み", "飲み込むと痛い"],
    },
    # gastrointestinal
    "복통": {
        "en": ["stomach pain", "belly pain", "abdominal pain"],
        "ko": ["배가 아파요", "배가 찢어질 듯 아파요", "명치가 아파요"],
        "zh": ["肚子疼", "胃痛", "腹部疼痛"],
        "ja": ["お腹が痛い", "胃が痛い", "腹部の痛み"],
    },
    "구토": {
        "en": ["throwing up", "vomiting", "emesis"],
        "ko": ["토했어요", "토가 나와요", "구역질 나고 토해요"],
        "zh": ["吐了", "想吐", "呕吐"],
        "ja": ["吐いた", "吐きました", "嘔吐"],
    },
    "메스꺼움": {
        "en": ["nausea", "feeling sick", "queasy"],
        "ko": ["속이 울렁거려요", "구역질 나요", "울렁거려요"],
        "zh": ["恶心", "反胃", "想吐"],
        "ja": ["吐き気", "ムカムカする", "気持ち悪い"],
    },
    "설사": {
        "en": ["diarrhea", "loose stool", "runny stool"],
        "ko": ["설사를 해요", "변이 묽어요", "물설사예요"],
        "zh": ["腹泻", "拉肚子", "稀便"],
        "ja": ["下痢", "軟便", "便がゆるい"],
    },
    # neurological
    "두통": {
        "en": ["headache", "migraine (if applicable)", "head pain"],
        "ko": ["머리가 아파요", "머리가 지끈거려요", "편두통 같아요"],
        "zh": ["头痛", "偏头痛", "脑袋疼"],
        "ja": ["頭が痛い", "頭痛", "偏頭痛"],
    },
    "어지럼": {
        "en": ["dizziness", "feeling dizzy", "vertigo (if spinning)"],
        "ko": ["어질어질해요", "빙글빙글 돌아요", "눈앞이 핑 돌아요"],
        "zh": ["头晕", "眩晕", "天旋地转"],
        "ja": ["めまい", "ふらふらする", "くらくらする"],
    },
    "말 어눌함": {
        "en": ["slurred speech", "speech is unclear"],
        "ko": ["말이 잘 안 나와요", "말이 꼬여요", "발음이 이상해요"],
        "zh": ["说话含糊", "言语不清"],
        "ja": ["ろれつが回らない", "言葉がはっきりしない"],
    },
    # emergency chest
    "흉통": {
        "en": ["chest pain", "pain in the chest"],
        "ko": ["가슴이 아파요", "가슴 통증이 있어요", "가슴이 찌릿해요"],
        "zh": ["胸痛", "胸口疼", "胸部疼痛"],
        "ja": ["胸が痛い", "胸痛", "胸の痛み"],
    },
    "가슴 압박감": {
        "en": ["chest pressure", "tightness in chest", "squeezing feeling in chest"],
        "ko": ["가슴이 답답해요", "가슴이 눌리는 느낌", "가슴이 조여요"],
        "zh": ["胸闷", "胸口压迫感", "胸口发紧"],
        "ja": ["胸が苦しい", "圧迫感", "締めつけられる感じ"],
    },
    "심계항진": {
        "en": ["palpitations", "heart racing", "heart pounding"],
        "ko": ["심장이 두근거려요", "심장이 빨리 뛰어요", "가슴이 두근두근해요"],
        "zh": ["心悸", "心跳加快", "心跳很快"],
        "ja": ["動悸", "心臓がドキドキする", "脈が速い"],
    },
    "실신": {
        "en": ["fainting", "syncope", "passed out"],
        "ko": ["기절했어요", "의식을 잃었어요", "쓰러졌어요"],
        "zh": ["晕倒", "晕厥", "失去意识"],
        "ja": ["失神", "気を失った", "倒れた"],
    },
    # skin/allergy
    "발진": {
        "en": ["rash", "skin rash", "breakout"],
        "ko": ["두드러기 같아요", "피부에 뭐가 났어요", "피부가 붉어졌어요"],
        "zh": ["皮疹", "起疹子", "皮肤发疹"],
        "ja": ["発疹", "湿疹みたい", "赤いぶつぶつ"],
    },
    "가려움": {
        "en": ["itching", "itchy"],
        "ko": ["가려워요", "간지러워요", "너무 가려워요"],
        "zh": ["痒", "瘙痒", "很痒"],
        "ja": ["かゆい", "かゆみ", "すごくかゆい"],
    },
    "두드러기": {
        "en": ["hives", "urticaria"],
        "ko": ["두드러기가 났어요", "붉게 올라와요", "올라왔어요"],
        "zh": ["荨麻疹", "风疹块"],
        "ja": ["蕁麻疹", "じんましん"],
    },
}

# Some lightweight automatic alias generation rules for Korean
KO_RULES = [
    # (pattern, replacement options)
    (r"통증", ["아픔", "아파요", "통증이 있어요"]),
    (r"곤란", ["힘들어요", "어려워요", "잘 안돼요"]),
    (r"부종", ["붓기", "부었어요", "부어요"]),
    (r"발열", ["열이 나요", "열이 있어요", "고열"]),
    (
        r"오한",
        ["추워요", "몸이 떨려요", "寒気 느낌"],
    ),  # last one is mixed; you can remove if you want pure KO
]

EN_RULES = {
    # canonical -> extra common phrasings
    "pain": ["ache", "soreness", "discomfort"],
    "difficulty": ["trouble", "hard time"],
}

# --------------------------------------------------
# 3) Helper functions
# --------------------------------------------------


def uniq(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        x2 = x.strip()
        if not x2:
            continue
        if x2 not in seen:
            seen.add(x2)
            out.append(x2)
    return out


def auto_aliases_ko(ko: str) -> List[str]:
    """
    Generate Korean conversational variants from canonical Korean term.
    Safe, conservative rules (do not change meaning).
    """
    aliases = []

    # Generic conversational wrappers
    aliases += [f"{ko} 있어요", f"{ko}입니다"] if len(ko) <= 6 else []
    aliases += (
        [f"{ko}가 있어요", f"{ko}가 있어요."] if not ko.endswith(("음", "함")) else []
    )
    aliases += (
        [f"{ko}이 있어요", f"{ko}이 심해요"] if ko.endswith(("통", "통증")) else []
    )

    # Common patient-style paraphrases for "X통증" -> "X가 아파요"
    if ko.endswith("통증"):
        base = ko.replace("통증", "")
        base = base.strip("() ")
        if base:
            aliases += [f"{base}이 아파요", f"{base}가 아파요", f"{base}이/가 아파요"]

    # Apply rule-based substitutions
    for pattern, reps in KO_RULES:
        if re.search(pattern, ko):
            for rep in reps:
                # simple replacement
                aliases.append(re.sub(pattern, rep, ko))
                # patient style
                aliases.append(re.sub(pattern, rep, ko) + " 있어요")

    # Common “~해요” ending
    if ko.endswith("함"):
        aliases.append(ko.replace("함", "해요"))
        aliases.append(ko.replace("함", "합니다"))

    # Remove awkward duplicates
    return uniq(aliases)


def auto_aliases_en(en: str) -> List[str]:
    """
    Generate English variants: conversational + clinical term hints
    """
    aliases = [en]

    # conversational
    if "pain" in en:
        aliases += ["it hurts", "I'm in pain", "painful", "I have pain"]
    if "shortness of breath" in en or "breath" in en:
        aliases += ["I can't breathe well", "hard to breathe", "trouble breathing"]
    if "nausea" in en:
        aliases += ["feel nauseous", "feel sick", "queasy"]
    if "vomiting" in en:
        aliases += ["throwing up", "threw up"]
    if "diarrhea" in en:
        aliases += ["loose stools", "runny stool"]

    # generic replacements
    for key, repls in EN_RULES.items():
        if key in en:
            for r in repls:
                aliases.append(en.replace(key, r))

    return uniq([a for a in aliases if a != en])  # keep only aliases, not canonical


def default_aliases_zh(zh: str) -> List[str]:
    """
    Conservative Chinese aliases. Avoid slang that changes meaning too much.
    """
    mapping = {
        "头晕": ["眩晕", "晕乎乎"],
        "呕吐": ["吐", "想吐"],
        "恶心": ["反胃", "想吐"],
        "腹泻": ["拉肚子", "稀便"],
        "胸痛": ["胸口疼", "胸部疼痛"],
        "胸闷": ["胸口发闷", "胸口压着"],
        "发热": ["发烧", "高烧"],
        "皮疹": ["出疹子", "起疹子"],
        "瘙痒": ["很痒", "发痒"],
        "呼吸困难": ["喘不过气", "呼吸费力", "气促"],
    }
    return uniq(mapping.get(zh, []))


def default_aliases_ja(ja: str) -> List[str]:
    """
    Conservative Japanese aliases.
    """
    mapping = {
        "めまい": ["くらくらする", "ふらふらする"],
        "嘔吐": ["吐いた", "吐きました"],
        "吐き気": ["ムカムカする", "気持ち悪い"],
        "下痢": ["便がゆるい", "軟便"],
        "胸痛": ["胸が痛い", "胸の痛み"],
        "胸やけ": ["胸が焼ける感じ"],
        "発熱": ["熱がある", "高熱"],
        "発疹": ["赤いぶつぶつ", "湿疹みたい"],
        "かゆみ": ["かゆい", "すごくかゆい"],
        "呼吸困難": ["息が苦しい", "息がしづらい"],
        "動悸": ["心臓がドキドキする", "脈が速い"],
    }
    return uniq(mapping.get(ja, []))


def build_entry(
    counter: int, scenario: str, ko: str, en: str, zh: str, ja: str
) -> Dict:
    base = {
        "term_id": f"S_{counter:04d}",
        "type": "symptom",
        "priority": "tier1",
        "scenario": scenario,
        "ko": ko,
        "en": en,
        "zh": zh,
        "ja": ja,
        "aliases": {"ko": [], "en": [], "zh": [], "ja": []},
    }

    # 1) curated overrides if exists
    curated = CURATED_ALIASES.get(ko)
    if curated:
        base["aliases"]["ko"] = curated.get("ko", [])
        base["aliases"]["en"] = curated.get("en", [])
        base["aliases"]["zh"] = curated.get("zh", [])
        base["aliases"]["ja"] = curated.get("ja", [])

    # 2) add auto aliases conservatively (merge + dedup)
    base["aliases"]["ko"] = uniq(base["aliases"]["ko"] + auto_aliases_ko(ko))
    base["aliases"]["en"] = uniq(base["aliases"]["en"] + auto_aliases_en(en))
    base["aliases"]["zh"] = uniq(base["aliases"]["zh"] + default_aliases_zh(zh))
    base["aliases"]["ja"] = uniq(base["aliases"]["ja"] + default_aliases_ja(ja))

    # 3) remove canonical duplicates if present
    for lang_key, canonical in [("ko", ko), ("en", en), ("zh", zh), ("ja", ja)]:
        base["aliases"][lang_key] = [
            a for a in base["aliases"][lang_key] if a != canonical
        ]

    return base


# --------------------------------------------------
# 4) Build up to 150 entries & save
# --------------------------------------------------


def build_symptom_entries(max_items: int = 150) -> List[Dict]:
    entries: List[Dict] = []
    counter = 1

    for scenario, items in SYMPTOM_SCENARIOS.items():
        for ko, en, zh, ja in items:
            if counter > max_items:
                return entries
            entries.append(build_entry(counter, scenario, ko, en, zh, ja))
            counter += 1

    return entries


def save_tier1_symptoms(
    filepath: str = "symptoms_tier1_auto_alias.json", max_items: int = 150
):
    data = build_symptom_entries(max_items=max_items)
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"✅ Saved {len(data)} Tier1 symptom entries with aliases → {filepath}")


if __name__ == "__main__":
    save_tier1_symptoms()
