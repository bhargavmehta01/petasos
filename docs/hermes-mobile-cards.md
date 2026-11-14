# Petasos cards: how Hermes replies render on the phone

Petasos shows agent replies as a texting thread. Short prose goes in left
bubbles. Everything structured becomes a **card**. The app builds cards in two
ways:

1. **Automatically from normal Markdown.** No agent changes needed.
2. **From an explicit `hermes-mobile-card` block** that the agent emits when it wants a
   specific layout (an order to approve, an event to add, a long summary).

Unknown or invalid blocks never break a reply: they fall back to a code card.

## 1. Automatic cards from Markdown

| Markdown in the reply | Card on the phone |
|---|---|
| A line that is only a link: `[Title](https://…)`, `- [Title](https://…) - note`, `Label: https://…`, or a bare `https://…` line | Link cards (one wide card, or a horizontal row when there are several). Shows favicon, title, domain. |
| A GFM table (`| a | b |` + `|---|---|`) | Table card. A short `**Bold**` or `### Heading` line right above the table becomes the card title. Long tables show 6 rows and a "Show all" button. |
| A fenced code block (```` ```bash ````) | Code card with language label and Copy. |
| `MEDIA:/path/on/host/file.ext` on its own line (Hermes' file delivery tag) | File card. Remote `https://` images render as a picture. |
| Inline links inside a sentence | Stay inline (tappable), no card. |

Tool calls never appear as text. Each run shows one compact **task card**
(title, current step, expandable steps, Stop). Model reasoning sits behind a
small "Thinking" disclosure.

## 2. Structured `hermes-mobile-card` blocks

Emit a fenced block with the language `hermes-mobile-card` and one JSON object. Every
object needs a `"type"`. One block = one card. Put prose before or after the
block as usual.

````markdown
Your cart is ready.

```hermes-mobile-card
{"type":"order_summary","merchant":"Costco","items":[{"name":"Milk","qty":1,"price":13.99}],"total":13.99}
```
````

### `text`
```json
{"type":"text","title":"Heads up","body":"Markdown **allowed**."}
```

### `links`
```json
{"type":"links","title":"Sources","links":[
  {"title":"City Botanical Garden","url":"https://example.org/garden","description":"Garden lights, Sat 6:30"}
]}
```

### `table`
```json
{"type":"table","title":"EV chargers","columns":["Charger","Amps","Price"],
 "rows":[["ChargePoint Home Flex","50 A","$549"],["Emporia","48 A","$399"]]}
```

### `summary` (long Markdown in a collapsible card)
```json
{"type":"summary","title":"Full fix log","markdown":"1. Reproduced…\n2. Patched…","collapsed":true}
```
`collapsed` defaults to `true`; set `false` to open it by default.

### `order_summary` (merchant, line items, total, approve button)
```json
{"type":"order_summary","merchant":"Costco Same-Day","status":"Ready",
 "currency":"$",
 "items":[{"name":"Organic milk 3-pack","qty":1,"price":13.99},{"name":"Bananas","qty":2,"price":1.99}],
 "subtotal":17.97,"fees":3.99,"tax":0,"tip":0,"total":21.96,
 "note":"Delivery today 5–6 pm",
 "approve_label":"Approve and order",
 "approve_prompt":"Approved. Place the Costco order now."}
```
Tapping the button **sends `approve_prompt` as the user's next chat message**
(default: "Approved. Go ahead and place the <merchant> order."). Nothing is
bought by the app itself; the agent acts on the reply. Set `"approvable": false`
to hide the button (for receipts).

### `calendar` (with "Add to calendar")
```json
{"type":"calendar","title":"Garden lights","start":"2026-11-07T18:30:00-05:00",
 "end":"2026-11-07T20:30:00-05:00","location":"100 Garden Way, Springfield",
 "description":"Tickets in email"}
```
Use ISO 8601 with an offset. "Add to calendar" opens a Google Calendar event
template (Android hands it to the Calendar app).

### `images`
```json
{"type":"images","title":"Options","images":[{"url":"https://…/a.jpg","caption":"Blue"},"https://…/b.jpg"]}
```

## Telling Hermes to use cards

Add something like this to your Hermes `SOUL.md` (or a `hermes-mobile-cards` skill):

```text
When replying to the Petasos phone app:
- Keep prose short (1-3 sentences per paragraph).
- Put sources on their own lines as Markdown links, one per line.
- Use GFM tables for comparisons; put a short **Bold title** line above them.
- For anything I must approve (purchases, bookings), emit a ```hermes-mobile-card block
  of type order_summary and wait for my "Approved" reply before acting.
- For events, emit a ```hermes-mobile-card calendar block with ISO times and offsets.
- Put long logs or reports in a ```hermes-mobile-card summary block.
- Card JSON must be one valid object on its own fenced block.
```

The parser lives in `lib/hermes_mobile/cards/blocks.dart` and the widgets in
`lib/hermes_mobile/cards/card_widgets.dart`. Tests: `test/hermes_mobile/hermes_mobile_cards_test.dart`.
