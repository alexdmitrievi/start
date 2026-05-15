# CALCULATOR LOGIC — Multi-Step Qualification Wizard
## Business Logic Document v1.0

---

## ARCHITECTURE OVERVIEW

```
Entry → Step 1 (Region) → Step 2 (Status) → Step 3 (Family)
     → Step 4 (Income) → Step 5 (Business Idea) → Step 6 (Direction)
     → Step 7 (Complications) → Step 8 (Reporting) → Contact
     → Score Reveal → CTA Branch
```

**Scoring type:** Weighted additive  
**Score range:** 15 (floor) – 92 (ceiling)  
**Complication model:** Flag system — complexity modifies RESULT TYPE, not outcome finality  
**Core rule:** Every result has a forward path. Zero dead ends.

---

## STEP-BY-STEP QUESTION ARCHITECTURE

---

### STEP 1 — REGION
*Weight: up to 10 points*
*Purpose: Regional budget activity strongly predicts approval probability*

**UI:** Searchable dropdown with regional grouping

**Helper text:**
> "Размер и активность программы социального контракта значительно
> варьируется по регионам. Это один из самых влиятельных факторов."

**Region Groups & Points:**

```
TIER A — 10 points
Высокая активность программы
  • Москва и Московская область
  • Санкт-Петербург и Ленинградская область
  • Республика Татарстан
  • Республика Башкортостан
  • Краснодарский край
  • Свердловская область
  • Новосибирская область
  • Нижегородская область
  • Самарская область
  • Ростовская область
  • Челябинская область
  • Пермский край
  • Красноярский край
  • Воронежская область
  • Саратовская область
  • Омская область
  • Волгоградская область

TIER B — 7 points
Средняя активность
  • Все остальные субъекты РФ не из списков A и C

TIER C — 5 points
Ограниченные данные / меньший бюджет
  • Ненецкий АО
  • Чукотский АО
  • Еврейская АО
  • Магаданская область
  • Республика Алтай
  • Республика Тыва
  • Республика Ингушетия

DEFAULT — 7 points
  • "Не знаю / уточню позже"
```

**Score logic:**
```
region_score = TIER_A ? 10 : TIER_C ? 5 : 7
```

---

### STEP 2 — STATUS
*Weight: up to 20 points*
*Purpose: Legal employment status is the primary eligibility qualifier*

**UI:** Large selection cards (not radio buttons), 1 column mobile / 2 columns tablet

**Helper text:**
> "Статус влияет на то, по какой программе вы можете подать.
> Некоторые статусы открывают больше направлений."

**Options & Points:**

```
CARD 1 — "Безработный"
  Subtext: "Состою на учёте в Центре занятости (ЦЗН)"
  Points:  20  ← highest priority category
  Flag:    PRIORITY_STATUS

CARD 2 — "Безработный (не на учёте)"
  Subtext: "Официально нигде не работаю, но не зарегистрирован"
  Points:  15
  Flag:    SUGGEST_REGISTER_CZN

CARD 3 — "Самозанятый"
  Subtext: "Зарегистрирован как плательщик НПД"
  Points:  15
  Flag:    none

CARD 4 — "ИП (предприниматель)"
  Subtext: "Зарегистрированный индивидуальный предприниматель"
  Points:  12
  Flag:    IP_STATUS  ← informational, not negative

CARD 5 — "Работаю по найму"
  Subtext: "Официально трудоустроен, но доход низкий"
  Points:  10
  Flag:    EMPLOYED_LOW_INCOME

CARD 6 — "Ранее получил отказ"
  Subtext: "Подавал на социальный контракт, получил отказ"
  Points:  8
  Flag:    PREVIOUS_REJECTION → adds STRATEGY_NEEDED context

CARD 7 — "Другое"
  Subtext: "Другой статус или комбинация"
  Points:  8
  Flag:    NEEDS_CLARIFICATION
```

**Score logic:**
```
status_score = selected_card.points
status_flags = selected_card.flags  ← carried through to result screen
```

---

### STEP 3 — FAMILY COMPOSITION
*Weight: up to 10 points*
*Purpose: Family income per capita is the core eligibility criterion*

**UI:** Step-form with counter inputs + toggle cards

**Section label:** "Состав семьи"

**Helper text (prominent, not dismissable):**
> "Социальный контракт рассчитывается на среднедушевой доход семьи.
> Чем больше семья при том же доходе — тем выше шансы на соответствие
> критериям. Укажите всех, с кем вы ведёте совместное хозяйство."

**Fields:**

```
FIELD 1 — Общий размер семьи
  Type:    Number stepper (1-10+)
  Label:   "Сколько человек в семье (включая вас)"
  Default: 1
  Min: 1, Max: 10+

TOGGLE — Есть супруг(а) / партнёр
  Type:    Single toggle
  Label:   "Есть супруг(а) или сожитель(ница)"
  Effect:  Adds to household size if not already counted

COUNTER — Дети
  Type:    Number stepper
  Label:   "Несовершеннолетние дети"
  Subtext: "До 18 лет, или до 23 при очной учёбе"
  Default: 0
  
TOGGLE — Живу один(а)
  Type:    Single toggle  
  Label:   "Живу один, семьи нет"
  Effect:  Sets family_size = 1, clears other fields

COMPUTED DISPLAY (shown dynamically, not a field):
  "Ваша семья: [N] человек"
  ← updates in real-time as user fills fields
```

**Scoring matrix:**

```
SCENARIO A: Single parent + 1 child = 10 pts
SCENARIO B: Single parent + 2+ children = 10 pts
SCENARIO C: Family with 3+ children (large family) = 10 pts
SCENARIO D: Family with 1-2 children = 8 pts
SCENARIO E: Living alone = 7 pts
SCENARIO F: Couple, no children = 5 pts
SCENARIO G: 2+ adults, no children = 4 pts

family_score = derive_from_composition(size, has_spouse, children_count)
```

---

### STEP 4 — INCOME
*Weight: up to 20 points*
*Purpose: Income-to-threshold ratio is the quantitative eligibility gate*

**UI:** Dual-field form with inline calculator

**Section label:** "Доходы семьи"

**Field 1 — Monthly family income:**
```
Label:   "Совокупный ежемесячный доход семьи"
Type:    Number input, formatted (₽)
Placeholder: "0 ₽"
Helper:  "Суммируйте все официальные и неофициальные доходы:
          зарплаты, пенсии, пособия, самозанятость, подработки"
Subtext: "Округлите до тысячи рублей. Точность здесь важнее, чем занижение."
```

**Field 2 — Regional threshold (dynamic):**
```
Label:    "Прожиточный минимум в вашем регионе"
Type:     Pre-populated based on Step 1 region selection
          If region selected → auto-fill with known PM value
          If "Другое" → manual input field
Helper:   "Это официальный прожиточный минимум для трудоспособного
          населения вашего региона на текущий год"
Subtext:  [link icon] "Актуальные данные: Росстат / региональное правительство"
```

**Auto-populated regional thresholds (2025 approximate values, RUB):**
```
Москва:           25 000
Санкт-Петербург:  17 400
Московская обл:   16 500
Прочие регионы:   from 13 500 to 20 000 (loaded from config)
```

**Computed display (real-time):**
```
Box: "Среднедушевой доход вашей семьи"
     Formula: monthly_income / family_size
     Displayed: "≈ [X] ₽ в месяц на человека"
     
     vs.
     
     Regional PM: "[PM] ₽"
     
     RATIO DISPLAY:
     If below PM:    "Ниже прожиточного минимума [badge: green]"
     If 100-120% PM: "Незначительно выше — возможно по ряду программ [badge: yellow]"
     If above 150%:  "Выше порога — актуально направление бизнес-старт [badge: blue]"
```

**Scoring matrix:**

```
per_capita = monthly_income / family_size
ratio      = per_capita / regional_pm

ratio < 0.50  → 20 pts  (deeply below threshold)
ratio 0.50–0.75 → 17 pts
ratio 0.75–1.00 → 13 pts
ratio 1.00–1.20 → 7 pts  (slightly above, business direction still possible)
ratio 1.20–1.50 → 4 pts
ratio > 1.50    → 2 pts  (business start direction only, very niche)

income_score = matrix[ratio]
```

**Edge case:** If income = 0 → 20 pts + flag NO_INCOME

---

### STEP 5 — BUSINESS IDEA
*Weight: up to 15 points*
*Purpose: Preparation level signals ability to create a viable business plan*

**UI:** Multi-select checkboxes with optional text field

**Section label:** "Ваша бизнес-идея"

**Helper text:**
> "Социальный контракт не требует готового бизнес-плана при подаче —
> но комиссия оценивает реалистичность намерений. Отметьте всё, что есть."

**Options (multi-select):**

```
CHECKBOX 1 — "Есть конкретная идея"
  Subtext: "Знаю, чем хочу заниматься и в каком направлении"
  Points:  +5

CHECKBOX 2 — "Есть опыт в этой сфере"
  Subtext: "Работал в этой области или делал похожее раньше"
  Points:  +4

CHECKBOX 3 — "Есть примерный расчёт затрат"
  Subtext: "Понимаю, что нужно купить и сколько это стоит"
  Points:  +4

CHECKBOX 4 — "Нужна помощь с оформлением"
  Subtext: "Хочу разобраться, как всё правильно написать"
  Points:  +2 (not a negative — shows self-awareness)
  Flag:    WANTS_HELP_WITH_PLAN

CHECKBOX 5 — "Пока не знаю, с чего начать"
  Subtext: "Нужна помощь с выбором направления"
  Points:  +1
  Flag:    NEEDS_DIRECTION_HELP
```

**Scoring matrix:**
```
business_score = sum(checked_options.points)
Max: 5 + 4 + 4 = 13 (realistic max without inflating)
Note: WANTS_HELP_WITH_PLAN adds 2 pts + flag, does not subtract
```

**If nothing selected:**
```
business_score = 0
Flag: NO_IDEA_YET
Message shown: "Ничего страшного — помощь с выбором направления 
                входит в консультацию"
```

---

### STEP 6 — DIRECTION (28 Federal Categories)
*Weight: up to 10 points*
*Purpose: Category alignment with regional budget priorities*

**UI:** Grid of category cards, searchable, grouped

**Helper text:**
> "Выберите направление, которое вам ближе всего.
> Если не уверены — выберите 'Не определился', это не снизит оценку."

**28 Categories (grouped):**

```
GROUP: ЗАНЯТОСТЬ И ЛИЧНОЕ РАЗВИТИЕ
  1.  Поиск работы и трудоустройство
      Points: 10 | Priority: HIGH
      Subtext: "Помощь в поиске работы, переобучение"

  2.  Профессиональное обучение / переобучение
      Points: 10 | Priority: HIGH
      Subtext: "Получить профессию или освоить новые навыки"

GROUP: ЛИЧНОЕ ПОДСОБНОЕ ХОЗЯЙСТВО
  3.  Развитие ЛПХ (личное подсобное хозяйство)
      Points: 10 | Priority: HIGH
      Subtext: "Огород, сад, небольшое хозяйство для семьи"

  4.  Животноводство и птицеводство
      Points: 10 | Priority: HIGH
      Subtext: "Куры, кролики, коровы, козы и пр."

  5.  Пчеловодство
      Points: 9 | Priority: HIGH
      Subtext: "Разведение пчёл, производство мёда"

  6.  Тепличное овощеводство / садоводство
      Points: 9 | Priority: HIGH
      Subtext: "Огурцы, томаты, зелень в теплице"

  7.  Рыбоводство
      Points: 8 | Priority: MEDIUM

GROUP: ПРОИЗВОДСТВО И РЕМЁСЛА
  8.  Деревообработка / столярные работы
      Points: 8 | Priority: MEDIUM
      Subtext: "Мебель, изделия из дерева, отделка"

  9.  Швейное / текстильное производство
      Points: 8 | Priority: MEDIUM

  10. Производство продуктов питания
      Points: 8 | Priority: MEDIUM
      Subtext: "Выпечка, кондитерские изделия, консервация"

  11. Хэндмейд / ремесленничество
      Points: 7 | Priority: MEDIUM
      Subtext: "Украшения, декор, сувениры, handmade"

GROUP: УСЛУГИ ДЛЯ НАСЕЛЕНИЯ
  12. Красота и здоровье
      Points: 8 | Priority: MEDIUM
      Subtext: "Парикмахерская, маникюр, массаж, косметология"

  13. Ремонтные услуги
      Points: 8 | Priority: MEDIUM
      Subtext: "Техника, авто, строительство, мелкий ремонт"

  14. Услуги по уходу за детьми
      Points: 10 | Priority: HIGH
      Subtext: "Нянечка, детский сад, мини-группы"

  15. Услуги по уходу за пожилыми
      Points: 10 | Priority: HIGH
      Subtext: "Сопровождение, уход, социальная помощь"

  16. Клининговые услуги
      Points: 7 | Priority: MEDIUM
      Subtext: "Уборка квартир, офисов, генеральные уборки"

  17. Услуги для животных
      Points: 7 | Priority: MEDIUM
      Subtext: "Груминг, передержка, выгул, ветпомощь"

GROUP: ОБРАЗОВАНИЕ И ТВОРЧЕСТВО
  18. Репетиторство / образовательные услуги
      Points: 8 | Priority: MEDIUM
      Subtext: "Обучение детей и взрослых"

  19. Музыкальные / творческие услуги
      Points: 7 | Priority: MEDIUM
      Subtext: "Уроки музыки, рисование, творческие кружки"

  20. Фото / видео производство
      Points: 7 | Priority: MEDIUM
      Subtext: "Фотограф, видеограф, монтажёр"

GROUP: ТЕХНОЛОГИИ И ОНЛАЙН
  21. IT-услуги / разработка / дизайн
      Points: 7 | Priority: MEDIUM
      Subtext: "Сайты, приложения, графика, контент"

  22. Онлайн-продажи / торговля
      Points: 7 | Priority: MEDIUM
      Subtext: "Маркетплейсы, интернет-магазин, перепродажа"

GROUP: ТРАНСПОРТ И ЛОГИСТИКА
  23. Транспорт и доставка
      Points: 7 | Priority: MEDIUM
      Subtext: "Перевозки, курьерская служба, такси"

GROUP: СЕЛЬСКОХОЗЯЙСТВЕННОЕ ПРОИЗВОДСТВО
  24. Растениеводство / фермерство
      Points: 9 | Priority: HIGH
      Subtext: "Поля, огороды в коммерческом масштабе"

  25. Переработка сельхозпродукции
      Points: 8 | Priority: MEDIUM

GROUP: ТУРИЗМ И МЕСТНЫЕ УСЛУГИ
  26. Туризм / гиды / местные экскурсии
      Points: 6 | Priority: LOWER
      Subtext: "Экотуризм, сельский туризм, экскурсионные услуги"

  27. Прокат оборудования / инструмента
      Points: 6 | Priority: LOWER
      Subtext: "Аренда инструментов, оборудования, инвентаря"

  28. Не определился / нужна помощь с выбором
      Points: 5 | Priority: DEFAULT
      Flag:   NEEDS_DIRECTION_SELECTION
      Message: "Это нормально — подберём подходящее направление
                исходя из вашей ситуации на консультации"
```

**Score logic:**
```
direction_score = selected_category.points
```

---

### STEP 7 — COMPLICATIONS
*Weight: Modifier (–15 to +10)*
*CRITICAL RULE: Complications change RESULT TYPE, not outcome finality*
*IRON LAW: Zero items in this step that map to "automatic rejection"*

**UI:** Multi-select cards with visual weight (not checkboxes — full cards)

**Section label:** "Есть ли особые обстоятельства?"

**Design instruction:**
Before the options, show this message in a prominent card:

```
[Info card — brand navy, amber icon]
HEADLINE: "Важно понять"
BODY:     "Сложные обстоятельства не означают автоматического отказа.
           В 80% случаев они меняют стратегию подачи, а не её возможность.
           Я лично проходил через многие из перечисленных ниже ситуаций."
```

**Options (multi-select):**

```
CARD 1 — "Налоговые долги"
  Subtext: "Задолженность перед ФНС (по налогам, штрафам, взносам)"
  Icon:    receipt-text (Lucide)
  Modifier: -3
  Flag:    TAX_DEBT
  Note:    "Не является автоматическим основанием для отказа"

CARD 2 — "Исполнительное производство (ФССП)"
  Subtext: "Активные производства приставов"
  Icon:    gavel (Lucide)
  Modifier: -5
  Flag:    FSSP_ACTIVE
  Triggers: MANUAL_REVIEW_REQUIRED

CARD 3 — "Арест счетов / имущества"
  Subtext: "Банковские счета или имущество под арестом"
  Icon:    lock (Lucide)
  Modifier: -5
  Flag:    FROZEN_ASSETS
  Triggers: MANUAL_REVIEW_REQUIRED

CARD 4 — "Статус ИП + сложности"
  Subtext: "Как предприниматель имею долги по обязательным платежам"
  Icon:    briefcase (Lucide)
  Modifier: -3
  Flag:    IP_COMPLICATIONS

CARD 5 — "Ранее получал отказ"
  Subtext: "По этой же или похожей программе"
  Icon:    x-circle (Lucide)
  Modifier: -5
  Flag:    REJECTION_HISTORY
  Triggers: STRATEGY_NEEDED

CARD 6 — "Нет источника дохода"
  Subtext: "Полностью без дохода сейчас"
  Icon:    wallet (Lucide)
  Modifier: -3
  Flag:    NO_INCOME_SOURCE
  Note:    "Нулевой доход может быть аргументом в пользу подачи"

CARD 7 — "Путаница с документами"
  Subtext: "Не уверен, что именно нужно собрать и в каком виде"
  Icon:    file-question (Lucide)
  Modifier: -2
  Flag:    DOCUMENT_CONFUSION

CARD 8 — "Ничего из перечисленного"
  Subtext: "Нет сложных обстоятельств"
  Icon:    check-circle (Lucide)
  Modifier: +10
  Flag:    CLEAN_CASE
  Exclusive: true  ← deselects all others if chosen
```

**Scoring logic:**
```
complication_modifiers = sum(selected_complications.modifier)

// Apply minimum floor
raw_subtotal = base_score + complication_modifiers
complication_adjusted = max(raw_subtotal, 15)

// Trigger determinations
manual_review = any(FSSP_ACTIVE, FROZEN_ASSETS)
strategy_needed = any(REJECTION_HISTORY, IP_COMPLICATIONS)
complex_case = count(selected) >= 3

// Messaging override rules
if manual_review → result_type = "MANUAL_REVIEW"
if strategy_needed AND NOT manual_review → result_type = "STRATEGY_NEEDED"
```

**After all options, show contextual note:**
```
if TAX_DEBT selected:
  "Налоговый долг — не запрет. Важно, как оформлена заявка."

if FSSP_ACTIVE selected:
  "Исполнительное производство требует ручного анализа. 
   У меня есть опыт с такими случаями."

if FROZEN_ASSETS selected:
  "Арест счетов — сложно, но не финально. 
   Разберём вашу ситуацию индивидуально."

if REJECTION_HISTORY selected:
  "Отказ — это не закрытая дверь. Часто нужно изменить стратегию,
   а не саму заявку."
```

---

### STEP 8 — REPORTING WILLINGNESS
*Weight: up to 7 points*
*Purpose: Commitment to reporting signals compliance reliability to reviewers*

**UI:** Single-select cards (4 options)

**Section label:** "Отчётность по контракту"

**Context text:**
> "Социальный контракт требует документального подтверждения того,
> как были потрачены средства. Это не сложнее, чем бухгалтерия ИП —
> но понимание этого заранее важно."

**Options:**

```
CARD 1 — "Да, готов(а) вести учёт и отчитываться"
  Subtext: "Понимаю, что нужно сохранять чеки и подавать отчёты"
  Points:  7

CARD 2 — "Готов(а), если помогут разобраться"
  Subtext: "Хочу понять, что именно нужно делать"
  Points:  4
  Flag:    WANTS_REPORTING_HELP

CARD 3 — "Не уверен(а), как это работает"
  Subtext: "Нужно больше информации"
  Points:  2
  Flag:    REPORTING_UNCERTAINTY

CARD 4 — "Беспокоит сложность отчётности"
  Subtext: "Боюсь не справиться с бухгалтерскими требованиями"
  Points:  0
  Flag:    REPORTING_ANXIETY
```

**Score logic:**
```
reporting_score = selected_card.points
```

---

## COMPLETE SCORING FORMULA

```
BASE SCORE CALCULATION:
───────────────────────
region_score      = 5–10   (Step 1)
status_score      = 8–20   (Step 2)
family_score      = 4–10   (Step 3)
income_score      = 2–20   (Step 4)
business_score    = 0–13   (Step 5)
direction_score   = 5–10   (Step 6)
reporting_score   = 0–7    (Step 8)

base_subtotal = sum(above)
max_base = 10+20+10+20+13+10+7 = 90

COMPLICATION MODIFIER:
──────────────────────
complication_modifier = sum(Step 7 modifiers)
range: -20 to +10

FINAL SCORE:
────────────
raw_score = base_subtotal + complication_modifier
final_score = clamp(raw_score, min=15, max=92)

Note: Score is always between 15 and 92.
Note: 92 is achievable by ideal candidate (registered unemployed,
      large family, deep below PM, clear funded idea, priority direction,
      no complications, ready to report)
```

---

## SCORE RANGES & RESULT TYPES

```
RANGE: 75–92 → HIGH_PROBABILITY
RANGE: 45–74 → MEDIUM_PROBABILITY
RANGE: 15–44 → NEEDS_STRATEGY

OVERRIDE RULES (take priority over score range):
  IF manual_review = true → RESULT_TYPE = COMPLEX_CASE
    (regardless of numeric score)
    Note: Score is still shown, but context changes
    
  IF complex_case = true (3+ complications) → 
    Add COMPLEX_CASE badge alongside score
```

---

## RESULT SCREENS — FULL SPECIFICATION

---

### RESULT A — HIGH PROBABILITY (75–92)

```
VISUAL:
  Score number:     Large, animated count-up (0 → final_score)
  Score color:      #10B981 (emerald)
  Background ring:  Emerald gradient arc (270° fill of 92)
  Badge:            "Высокий шанс" — emerald pill

HEADLINE:
  "Ваши шансы — высокие"

SUBHEADLINE:
  "Ваша ситуация соответствует большинству критериев программы"

BODY COPY:
  "Это не гарантия — но это один из лучших профилей, которые я вижу.
  Главное сейчас — не затягивать: региональные бюджеты на социальные
  контракты ограничены и заканчиваются в течение года."

KEY INSIGHTS (3 cards, based on answers):
  Dynamically generated from flagged strong points
  E.g.: "Ваш статус — приоритетная категория"
        "Доход ниже прожиточного минимума — вы в целевой группе"
        "Выбранное направление финансируется активно"

NEXT STEPS:
  1. "Запишитесь на консультацию — разберём конкретный план"
  2. "Подготовьте базовый пакет документов"
  3. "Не откладывайте: в [region] бюджет активен прямо сейчас"

PRIMARY CTA:   "Записаться на консультацию →"
SECONDARY CTA: "Написать в Telegram"
TERTIARY:      text link "Посмотреть, что входит в консультацию"
```

---

### RESULT B — MEDIUM PROBABILITY (45–74)

```
VISUAL:
  Score number:     Animated, amber/orange
  Score color:      #F59E0B (amber)
  Background ring:  Amber arc
  Badge:            "Шанс есть" — amber pill

HEADLINE:
  "Шанс есть — нужна правильная подготовка"

SUBHEADLINE:
  "Ваша ситуация неоднозначная, но не безнадёжная"

BODY COPY:
  "Именно такие случаи — между «легко» и «сложно» — требуют
  наиболее точного подхода. Небольшие изменения в стратегии подачи
  часто кардинально меняют результат."

SPECIFIC IMPROVEMENT HINTS (dynamic, from weak scoring factors):
  E.g.:
  If income_score was low but close to PM:
    "Уточните список всех доходов семьи — 
     иногда упускают пособия или льготы"
  If no_idea_yet:
    "Помощь с выбором и оформлением направления — 
     одна из самых полезных частей консультации"
  If document_confusion:
    "Разберём список документов под ваш регион"

KEY INSIGHTS (2–3 cards, dynamic):
  Generated from mid-range scoring factors

NEXT STEPS:
  1. "Поймите, что именно снижает ваши шансы"
  2. "Составьте стратегию с учётом слабых мест"
  3. "Подайте с правильной подготовкой, а не наугад"

PRIMARY CTA:   "Разобраться вместе в Telegram →"
SECONDARY CTA: "Записаться на консультацию"
SUBTLE NOTE:   "Большинство моих клиентов начинали именно с такого результата"
```

---

### RESULT C — NEEDS STRATEGY (15–44)

```
VISUAL:
  Score number:     Animated, slate/blue (NOT red — never negative)
  Score color:      #6B8DB5 (muted blue)
  Background ring:  Slate arc
  Badge:            "Требует стратегии" — slate pill

HEADLINE:
  "На первый взгляд непросто — но это не финал"

SUBHEADLINE:
  "Ваша ситуация требует индивидуального анализа"

BODY COPY (PERSONAL — this is where founder voice matters most):
  "Я получил социальный контракт с долгом 1,4 миллиона рублей и
  арестованными счетами. Низкий результат теста — это не отказ.
  Это сигнал, что нужна более точная стратегия, чем стандартный путь."

REFRAME MESSAGE:
  "Что это значит на самом деле:"
  • "Не всё зависит от одного критерия"
  • "Некоторые регионы рассматривают нестандартные случаи"
  • "Есть способы улучшить профиль до подачи"
  • "Отказ можно оспорить или переподать с другой стратегией"

SPECIAL OFFER:
  [card with amber border]
  "15-минутный экспресс-разбор — бесплатно"
  "Расскажите о ситуации. Скажу честно: есть путь или нет."
  [button: "Написать в Telegram"]

PRIMARY CTA:   "Получить честный разбор ситуации →"
SECONDARY CTA: "Записаться на полную консультацию"
NOTE:          "Если после анализа поймём, что шансов нет — скажу об этом прямо"
```

---

### RESULT D — COMPLEX CASE (complication override)

```
Triggered when: manual_review = true (FSSP / frozen accounts)
Score: shown as normal, but framed differently

VISUAL:
  Score badge:      "Нестандартный случай" — navy + amber
  Score ring:       Navy with amber accent
  Special icon:     compass (navigation metaphor)

HEADLINE:
  "Долги, приставы, арест счетов —
  это не конец разговора"

SUBHEADLINE:
  "Ваша ситуация похожа на мою в 2022 году"

FOUNDER'S STORY INSERT:
  [Quote card]
  "У меня было исполнительное производство и арест счетов.
   Сказали — невозможно. Я всё равно подал. И получил.
   Потому что знал, как правильно оформить."
  — [Founder name]

WHAT THIS MEANS:
  "Ваши обстоятельства требуют:"
  • "Ручного анализа конкретных документов"
  • "Понимания позиции именно вашего регионального комитета"
  • "Особой стратегии оформления заявки"
  • "Возможно — последовательности действий перед подачей"

CLEAR DISCLAIMER:
  [Note card, muted]
  "Я не обещаю результата. Но я скажу честно — после анализа —
   есть ли реальный путь в вашем случае."

PRIMARY CTA:   "Обсудить вашу ситуацию в Telegram →"
SECONDARY CTA: "Записаться на консультацию"
```

---

## CONTACT STEP — FULL SPECIFICATION

**Placement:** After result screen is shown, contact is below the fold on same screen

**UI principle:** Contact form is NOT a gate. Result is shown first, fully. 
Contact appears as "next step" below result, not before it.

**Section label:** "Как с вами связаться?"

**Fields:**

```
FIELD 1 — Имя
  Type:     Text input
  Label:    "Как вас зовут?"
  Required: Yes
  Placeholder: "Имя (или псевдоним)"
  Helper:   "Только имя — чтобы знать, как к вам обращаться"
  Validation: min 2 chars

FIELD 2 — Телефон
  Type:     Tel input, Russian format +7
  Label:    "Номер телефона"
  Required: No (marked "необязательно")
  Format:   +7 (___) ___-__-__
  Helper:   "Для WhatsApp / Telegram / звонка — на ваш выбор"

FIELD 3 — Telegram
  Type:     Text input
  Label:    "Telegram"
  Required: No
  Placeholder: "@username или номер"
  Helper:   "Самый быстрый способ связи"

FIELD 4 — Preferred messenger
  Type:     Single-select button group
  Label:    "Как вам удобнее общаться?"
  Options:
    [Telegram] [WhatsApp] [ВКонтакте] [Звонок] [Не важно]

FIELD 5 — Convenient time
  Type:     Multi-select chips (optional)
  Label:    "Удобное время (необязательно)"
  Options:  [Утро 9–12] [День 12–17] [Вечер 17–21] [В любое время]
```

**Personal data consent:**
```
CHECKBOX — Required
  Text: "Я соглашаюсь на обработку персональных данных"
  Link: [full text in modal, not external page]
  Style: Standard checkbox with text, no dark patterns
  
  Modal content:
  "Ваши данные (имя, контакты) используются исключительно для
   связи с вами по вопросу консультации. Данные не передаются третьим
   лицам, не продаются, хранятся на защищённом сервере. Вы можете
   запросить удаление данных в любое время, написав в Telegram."
```

**Submit button:**
```
Text:     "Отправить и посмотреть результат"
Style:    Full-width, amber, 56px height
Icon:     arrow-right
Loading:  Spinner during submit (300ms min display)
```

**Post-submit:**
```
Success state:
  Icon:    check-circle (large, emerald)
  Heading: "Готово — ваш результат отправлен"
  Body:    "Обычно отвечаю в течение нескольких часов.
            Если срочно — напишите напрямую в Telegram."
  CTA:     [Open Telegram →] (pre-filled message template)

Pre-filled Telegram message template:
  "Привет! Я только что прошёл(ла) тест на вашем сайте.
   Мой результат: [score] — [result_type].
   Хочу записаться на консультацию."
```

---

## SCORING EXAMPLES (QA reference)

```
EXAMPLE 1 — Ideal candidate (target: HIGH):
  Region:     Moscow Oblast (TIER A) = 10
  Status:     Registered unemployed = 20
  Family:     Single parent + 2 children = 10
  Income:     15000 / 3 people = 5000 vs PM 16500 (ratio 0.30) = 20
  Business:   Idea + experience + estimate = 13
  Direction:  Childcare services = 10
  Complication: None = +10
  Reporting:  Ready = 7
  TOTAL: 10+20+10+20+13+10+10+7 = 100 → capped at 92
  RESULT: HIGH PROBABILITY ✓

EXAMPLE 2 — Complex case (target: MEDIUM + COMPLEX FLAG):
  Region:     Voronezh (TIER A) = 10
  Status:     IP (entrepreneur) = 12
  Family:     Family 2+2 children = 8
  Income:     45000 / 4 = 11250 vs PM 13000 (ratio 0.86) = 10
  Business:   Idea + needs help = 7
  Direction:  Food production = 8
  Complication: Tax debt + FSSP active = -3 + -5 = -8
  Reporting:  Ready with help = 4
  TOTAL: 10+12+8+10+7+8+(-8)+4 = 51 → MEDIUM score
  COMPLEX FLAG: YES (FSSP_ACTIVE) → RESULT_TYPE = COMPLEX_CASE
  Display: Score 51 + "Нестандартный случай" badge
  RESULT: COMPLEX_CASE screen ✓

EXAMPLE 3 — Difficult case (target: NEEDS_STRATEGY):
  Region:     Chukotka (TIER C) = 5
  Status:     Employed (low income) = 10
  Family:     Living alone = 7
  Income:     25000 / 1 = 25000 vs PM 20000 (ratio 1.25) = 4
  Business:   Nothing selected = 0
  Direction:  Not decided = 5
  Complication: Previous rejection + no income + document confusion = -5-3-2 = -10
  Reporting:  Worried = 0
  TOTAL: 5+10+7+4+0+5+(-10)+0 = 21 → floored at 21
  RESULT: NEEDS_STRATEGY ✓
  
EXAMPLE 4 — Founder-like case (target: COMPLEX_CASE):
  Region:     Saratov (TIER A) = 10
  Status:     IP with complications = 12 (IP_COMPLICATIONS flag)
  Family:     Family 2 adults = 5
  Income:     0 (frozen accounts, no income) = 20 + NO_INCOME flag
  Business:   Idea + experience = 9
  Direction:  Services = 8
  Complication: Tax debt + FSSP + frozen accounts + IP = -3-5-5-3 = -16
  Reporting:  Ready = 7
  TOTAL: 10+12+5+20+9+8+(-16)+7 = 55 → capped above floor
  COMPLEX FLAG: YES (FSSP + FROZEN_ASSETS)
  RESULT: COMPLEX_CASE screen with founder story ✓
```

---

## PROGRESS BAR SPECIFICATION

```
VISUAL DESIGN:
  Type:     Segmented bar (8 segments + contact)
  Height:   4px (line) + label
  Active:   amber fill (#F59E0B)
  Complete: emerald fill (#10B981)  
  Inactive: brand-700 (dark grey)
  
  Label above bar:
    "Шаг [N] из 8 — [Step Name]"
    Font: --text-sm, --text-secondary
    
  Percentage (mobile, compact):
    "[N]/8"

SEGMENTS:
  1: Регион
  2: Статус
  3: Семья
  4: Доход
  5: Идея
  6: Направление
  7: Обстоятельства
  8: Отчётность
  (C): Контакт — shown separately after step 8

MOBILE BEHAVIOR:
  Dots only (8 dots, filled/empty)
  Tap-to-navigate: disabled (forward only, back allowed)
  Step label: above dots, centered
```

---

## TRANSITION & MICROINTERACTION SPEC

```
STEP TRANSITION:
  Exit:  slide-left + fade-out, 200ms ease-in
  Enter: slide-from-right + fade-in, 250ms ease-out
  Easing: cubic-bezier(0.4, 0.0, 0.2, 1)  // Material standard

CARD SELECTION:
  Unselected: border-brand-700, bg-brand-800
  Hover:      border-brand-400, bg-brand-700, transform scale(1.01), 150ms
  Selected:   border-accent-500, bg with amber tint, 
              check-circle icon appears (top-right), 200ms
  Multi-select: accumulate borders, no deselect-all

SCORE REVEAL:
  Score number: count-up animation
                0 → final_score, 1200ms
                Easing: ease-out cubic
  Color:        fades in at 800ms
  Ring arc:     draws from 0° to target angle, 1000ms, 200ms delay
  Badge:        slides up + fade, 1400ms
  CTAs:         stagger fade-up: 1600ms, 1800ms, 2000ms

BACK NAVIGATION:
  Allowed at every step
  Transition: reverse (slide-right)
  State: form values preserved in memory

INPUT VALIDATION:
  Income field: format number on blur (add ₽ separator)
  Error state: border-red-500 + error message below, shake animation (300ms)
  Required fields: highlight on Submit attempt only (not on blur)
```

---

## DYNAMIC CONTENT RULES (Personalization)

The calculator adapts displayed content based on accumulated answers:

```
RULE 1 — Status affects Step 5 helper text:
  If status = UNEMPLOYED:
    "В вашем случае важно показать, что бизнес-план реалистичен.
     Комиссия учитывает это."
  If status = IP:
    "Как действующий ИП вы можете подать на развитие существующего дела."
  If status = PREVIOUS_REJECTION:
    "Уточните, по какому именно направлению был отказ — 
     часто можно подать иначе."

RULE 2 — Region affects income helper text:
  If region selected:
    Auto-populate PM field with regional value
    Show: "В [регион] прожиточный минимум: [PM] ₽"

RULE 3 — Low income affects Step 5 messaging:
  If income_ratio < 0.75:
    "С вашим доходом вы в приоритетной группе по большинству направлений."

RULE 4 — Complications affect Step 8 framing:
  If any complication selected:
    Above Step 8:
    "Это последний вопрос. Готовность к отчётности — один из факторов,
     который можно улучшить до подачи."

RULE 5 — Previous rejection affects CTA copy:
  If REJECTION_HISTORY:
    Primary CTA → "Разработать стратегию повторной подачи →"

RULE 6 — High score + no complications:
  After step 7, show micro-celebration:
  "Отличный профиль. Вы близки к финишу."
```

---
