use("hyouji/kodou", [:link])

def flasher(parent)
  addr = receive()
  send(parent, link(addr, {channels: [:flash]}) rescue "swallowed")
end

def main()
  pid = spawn(flasher, [self])
  monitor(pid)
  send(pid, "127.0.0.1:0")
  write_stdout(to_s(receive(:_, 5000)))
end
