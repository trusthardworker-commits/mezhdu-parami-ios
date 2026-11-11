const byId = id => document.getElementById(id);
const weekdays = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"];
let database, group, chosenDate, timer;
function element(tag, value, className) {
  const node = document.createElement(tag);
  node.textContent = value;
  if (className) node.className = className;
  return node;
}
function showDate(date) {
  chosenDate = date;
  render();
}
function render() {
  const now = new Date();
  const target = displayDay(now);
  const date = chosenDate || target;
  const day = getDay(database.weeks, group, date);
  const key = dateKey(date);
  const monday = shiftDay(date, 1 - (date.getDay() || 7));
  byId("date").textContent = date.toLocaleDateString("ru-RU", {weekday:"long", day:"numeric", month:"long"});
  byId("week").textContent = day.weekTitle;
  byId("relative").textContent = key === dateKey(now) ? "Сегодня" : key === dateKey(shiftDay(now, 1)) ? "Завтра" : "";
  byId("days").replaceChildren(...weekdays.map((name, i) => {
    const d = shiftDay(monday, i);
    const btn = element("button", "");
    btn.append(element("small", name), element("span", d.getDate()));
    btn.setAttribute("aria-label", d.toLocaleDateString("ru-RU", {weekday:"long", day:"numeric", month:"long"}));
    btn.setAttribute("aria-pressed", String(dateKey(d) === key));
    btn.onclick = () => showDate(d);
    return btn;
  }));
  byId("prev").onclick = () => showDate(shiftDay(date, -7));
  byId("next").onclick = () => showDate(shiftDay(date, 7));
  byId("prev").disabled = dateKey(monday) <= database.weeks[0].start;
  byId("next").disabled = dateKey(shiftDay(monday, 7)) > database.weeks[database.weeks.length-1].end;
  byId("reset").hidden = !chosenDate;
  const rows = day.lessons.map(l => {
    const row = element("article", "", "lesson");
    const num = element("span", l.period || "День", "num");
    num.setAttribute("aria-label", l.period ? l.period + " пара" : "Весь день");
    const body = element("div", "");
    body.append(element("h3", l.title), element("p", l.details));
    row.append(num, body);
    return row;
  });
  byId("lessons").replaceChildren(...(day.message ? [element("p", day.message, "empty")] : rows));
  byId("warning").textContent = group.warning || "";
  byId("warning").hidden = !group.warning;
  byId("widgetgroup").textContent = group.id;
  byId("scriptname").textContent = "Пары " + group.id;
  clearTimeout(timer);
  timer = setTimeout(() => { chosenDate = null; render(); }, nextEvening(now) - now + 50);
  lastTarget = dateKey(target);
}
let lastTarget;
function resume() {
  if (!group) return;
  if (lastTarget !== dateKey(displayDay(new Date()))) chosenDate = null;
  render();
}
function selectGroup(id) {
  group = database.groups.find(g => g.id === id);
  byId("group").value = id;
  try { localStorage.setItem("fiteu-group", id); } catch {}
  const url = new URL(location.href);
  url.searchParams.set("group", id);
  history.replaceState(null, "", url);
  render();
}
async function start() {
  const response = await fetch("schedule.json");
  if (!response.ok) throw new Error("schedule");
  database = await response.json();
  const select = byId("group");
  for (const g of database.groups) select.add(new Option(g.id, g.id));
  let saved;
  try { saved = localStorage.getItem("fiteu-group"); } catch {}
  const choices = [new URL(location.href).searchParams.get("group"), saved, "23ПИжб"];
  const first = choices.find(id => database.groups.some(g => g.id === id)) || database.groups[0].id;
  selectGroup(first);
  select.disabled = false;
  select.onchange = () => selectGroup(select.value);
  byId("status").hidden = true;
  byId("content").hidden = false;
}
byId("reset").onclick = () => showDate(null);
let widgetScript = "";
let downloadURL;
let downloadVersion = 0;
async function prepareDownload() {
  const version = ++downloadVersion;
  const link = byId("download");
  const id = group.id;
  widgetScript = "";
  link.removeAttribute("href");
  byId("copy").disabled = true;
  byId("downloadstatus").textContent = "Готовим файл…";
  try {
    const response = await fetch("widgets/" + encodeURIComponent(id) + ".scriptable");
    if (!response.ok) throw new Error("widget");
    const pkg = await response.json();
    if (version !== downloadVersion) return;
    const base = new URL("./", document.baseURI).href;
    const siteLine = /^const siteURL = .*;$/m;
    if (!siteLine.test(pkg.script)) throw new Error("widget format");
    pkg.script = pkg.script.replace(siteLine, () => "const siteURL = " + JSON.stringify(base) + ";");
    const file = new Blob([JSON.stringify(pkg)], {type:"application/octet-stream"});
    if (downloadURL) URL.revokeObjectURL(downloadURL);
    downloadURL = URL.createObjectURL(file);
    link.href = downloadURL;
    link.download = id + ".scriptable";
    widgetScript = pkg.script;
    byId("copy").disabled = false;
    byId("downloadstatus").textContent = "";
  } catch {
    if (version === downloadVersion) byId("downloadstatus").textContent = "Не удалось загрузить файл. Проверь соединение и открой это окно ещё раз.";
  }
}
byId("setup").onclick = () => {
  byId("copystatus").textContent = "";
  byId("manual").hidden = true;
  byId("instructions").showModal();
  prepareDownload();
};
document.querySelector(".close").onclick = () => byId("instructions").close();
byId("copy").onclick = async () => {
  try {
    const script = widgetScript;
    if (!script) throw new Error("widget");
    try {
      await navigator.clipboard.writeText(script);
      byId("copystatus").textContent = "Код скопирован";
    } catch {
      const field = byId("manual");
      field.hidden = false;
      field.value = script;
      field.focus();
      field.select();
      byId("copystatus").textContent = "Выдели весь код и нажми «Скопировать».";
    }
  } catch { byId("copystatus").textContent = "Не удалось загрузить код. Попробуй ещё раз."; }
};
window.addEventListener("pageshow", resume);
document.addEventListener("visibilitychange", () => { if (!document.hidden) resume(); });
start().catch(() => { byId("status").textContent = "Не удалось загрузить расписание. Проверь соединение и обнови страницу."; });
