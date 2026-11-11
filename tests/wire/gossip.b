use("hyouji/kodou", %i[address link node publish step])
use("retsu", %i[first last])

def main()
  la = link("127.0.0.1:0", {})
  lb = link("127.0.0.1:0", {})
  a = reduce(
    (n, text) -> publish(n, address(lb), text),
    node(la, "IMMUNITY_A"),
    [CRASHES]
  )
  done = reduce(
    (acc, _i) -> [step(first(acc), 50, 16), step(last(acc), 50, 16)],
    [a, node(lb, "IMMUNITY")],
    range(ROUNDS)
  )
  b = last(done)
  write_stdout(
    json_stringify(
      {
        known: b.known,
        refused: b.refused,
        wanted: length(map_entries(b.wanted))
      }
    )
  )
end
