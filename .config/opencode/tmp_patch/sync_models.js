const fs = require('fs');

// Đọc response từ omniroute (chứa model, provider, status, error, latencyMs, ...)
const response = JSON.parse(fs.readFileSync('./response.json', 'utf8'));

// Trim: chỉ giữ lại field model + provider, group theo status
// Kết quả: { "ok": [{model, provider}, ...], "error": [{model, provider}, ...] }
const grouped = {};
for (const item of response) {
  const status = item.status;
  if (!grouped[status]) grouped[status] = [];
  grouped[status].push({ model: item.model, provider: item.provider });
}
fs.writeFileSync('./res_trim.json', JSON.stringify(grouped, null, 2) + '\n');

// Log summary per status group
for (const [status, items] of Object.entries(grouped)) {
  console.log(`[${status}] ${items.length} models`);
}

// Sync vào opencode.json: quét hết mọi group, thêm model mới vào omniroute.models
// Key = model-id của provider (dùng để gọi API)
// name = display name (hiện trong UI)
// Format: { [model-id]: { name: display-name } }
// Không edit model đã tồn tại
// Rule: name có suffix ":free" → đổi thành "free:MODEL" (ví dụ name "a/b:free" → "free:a/b")
// Key giữ nguyên model-id gốc
const opencode = JSON.parse(fs.readFileSync('../opencode.json', 'utf8'));
const existing = opencode.provider.omniroute.models;

// Fix name của existing models có suffix ":free"
for (const [key, val] of Object.entries(existing)) {
  if (val.name && val.name.endsWith(':free')) {
    val.name = 'free:' + val.name.slice(0, -5);
  }
}

function toName(model) {
  if (model.endsWith(':free')) return 'free:' + model.slice(0, -5);
  return model;
}

let added = 0;
let total = 0;

for (const [, items] of Object.entries(grouped)) {
  for (const item of items) {
    total++;
    if (!existing[item.model]) {
      existing[item.model] = { name: toName(item.model) };
      added++;
    }
  }
}

fs.writeFileSync('../opencode.json', JSON.stringify(opencode, null, 2) + '\n');
console.log(`\nSynced ${total} models → added ${added} new, skipped ${total - added} existing.`);
