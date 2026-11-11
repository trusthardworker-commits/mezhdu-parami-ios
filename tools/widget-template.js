const now = new Date();
const date = displayDay(now);
const day = getDay(weeks, group, date);
const widget = new ListWidget();
widget.backgroundColor = new Color("#173C36");
widget.setPadding(13, 14, 13, 14);
widget.refreshAfterDate = nextEvening(now);
widget.url = siteURL + "?group=" + encodeURIComponent(group.id);

function line(value, size, bold, color, limit = 1) {
  const label = widget.addText(value);
  label.textColor = new Color(color);
  label.font = bold ? Font.boldSystemFont(size) : Font.systemFont(size);
  label.lineLimit = limit;
  return label;
}

const large = config.widgetFamily === "large";
const small = config.widgetFamily === "small";
const formatter = new DateFormatter();
formatter.locale = "ru_RU";
formatter.dateFormat = "EEE, d MMM";
line(group.id + "  ·  " + formatter.string(date), small ? 13 : 16, true, "#FFFFFF");
if (day.weekTitle) line(day.weekTitle, 11, false, "#C9E3BA");
widget.addSpacer(6);
if (day.message) line(day.message, 14, false, "#FFFFFF", 3);
const capacity = large ? 6 : small ? 2 : 3;
for (const lesson of day.lessons.slice(0, capacity)) {
  const prefix = lesson.period ? lesson.period + " · " : "";
  line(prefix + lesson.title, small ? 12 : 14, true, "#FFFFFF");
  if (large && lesson.details) line(lesson.details, 11, false, "#DBE7E2");
  widget.addSpacer(3);
}
if (day.lessons.length > capacity) line("Ещё занятий: " + (day.lessons.length - capacity), 11, false, "#C9E3BA");
if (group.warning && !small) line("Есть примечание к расписанию группы", 10, false, "#FFDA9F");
widget.addSpacer();
Script.setWidget(widget);
if (!config.runsInWidget) await widget.presentMedium();
Script.complete();
