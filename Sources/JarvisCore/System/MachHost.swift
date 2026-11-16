import Darwin

let machHost: mach_port_t = mach_host_self()

func sysctlValue<Value>(_ name: String, as type: Value.Type) -> Value? {
  var size = MemoryLayout<Value>.size
  let pointer = UnsafeMutablePointer<Value>.allocate(capacity: 1)
  defer { pointer.deallocate() }
  guard sysctlbyname(name, pointer, &size, nil, 0) == 0, size == MemoryLayout<Value>.size else {
    return nil
  }
  return pointer.pointee
}
