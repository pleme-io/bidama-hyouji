use("hyouji/kodou", %i[address emit link])
use("retsu", %i[first last push])

def payload(i)
  join(map((_k) -> "x", range(i * 397 % 1280)), "")
end

def main()
  a = link("127.0.0.1:0", {channels: [:flash]})
  b = link("127.0.0.1:0", {channels: [:flash]})
  peer = address(b)
  sends = reduce(
    fn(acc, i)
      l = emit(first(acc), peer, payload(i))
      got = flash_next(b.wire, 2000)
      [l, push(last(acc), [l.sent.at_ms, l.sent.bytes, got.bytes])]
    end,
    [a, []],
    range(40)
  )
  big = join(map((_k) -> "x", range(1280)), "")
  bucket = begin
    emit(a, peer, big)
    "sent"
  rescue _
    "refused"
  end
  host = begin
    flash_put(a.wire, peer, big)
    "sent"
  rescue _
    "refused"
  end
  write_stdout(
    json_stringify(
      {
        sends: last(sends),
        bucket:,
        host:,
        sent: flash_stats(a.wire).sent,
        received: flash_stats(b.wire).received,
        refused: flash_stats(a.wire).refused
      }
    )
  )
end
