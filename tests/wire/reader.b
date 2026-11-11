use("shisutemu", [:read_or])

def reader(parent)
  path = receive()
  send(parent, read_or(path, "") rescue "swallowed")
end

def main()
  pid = spawn(reader, [self])
  monitor(pid)
  send(pid, "/etc/hosts")
  write_stdout(to_s(receive(:_, 5000)))
end
