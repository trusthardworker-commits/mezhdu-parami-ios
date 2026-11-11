function shiftDay(date, offset) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + offset, 12);
}

function displayDay(now) {
  return shiftDay(now, now.getHours() >= 20 ? 1 : 0);
}

function dateKey(date) {
  return [date.getFullYear(), date.getMonth() + 1, date.getDate()]
    .map(value => String(value).padStart(2, "0")).join("-");
}

function nextEvening(now) {
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + (now.getHours() >= 20 ? 1 : 0), 20);
}

function getDay(weeks, group, date) {
  const key = dateKey(date);
  const week = weeks.find(w => w.start <= key && key <= w.end);
  const weekTitle = week ? (week.kind === "upper" ? "Верхняя неделя" : "Нижняя неделя") : "";
  let message = "";
  if (!week) message = "На эту дату нет календаря недель";
  else if (key < group.validFrom || key > group.validThrough) message = "На эту дату расписание не загружено";
  if (message) return { weekTitle, message, lessons: [] };
  const weekday = date.getDay() || 7;
  const matches = group.lessons.filter(l => {
    if (l.weekday !== weekday || l.startsOn > key || l.endsOn < key) return false;
    if (l.excludedDates && l.excludedDates.includes(key)) return false;
    if (l.onlyDates) return l.onlyDates.includes(key);
    return l.week === "both" || l.week === week.kind;
  });
  const overrides = new Set(matches.filter(l => l.onlyDates).map(l => l.period));
  const lessons = matches.filter(l => l.onlyDates || !overrides.has(l.period))
    .sort((a, b) => a.period - b.period || (a.id < b.id ? -1 : Number(a.id !== b.id)));
  return { weekTitle, lessons, message: lessons.length ? "" : "Пар нет по расписанию" };
}
