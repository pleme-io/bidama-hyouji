use("hyouji/kodou", %i[emit link pump queue])

def main()
  peer = "127.0.0.1:PORT"
  l = link("127.0.0.1:0", {channels: [:tide]})
  sent = pump(queue(l, peer, "control"))
  alerting = link(sent.wire, {channels: [:flash]})
  emit(alerting, peer, "alert") rescue write_stdout("swallowed")
  write_stdout("after")
end
