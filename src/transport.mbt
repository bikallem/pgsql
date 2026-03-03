///| Transport Abstraction
///
/// Abstracts over TCP and TLS connections so the rest of the driver
/// can read/write without knowing the underlying transport.

///|
/// Transport wraps either a plain TCP socket or a TLS connection.
priv enum Transport {
  PlainTcp(@socket.Tcp)
  TlsConn(@tls.Tls, @socket.Tcp)
}

///|
/// Write bytes to the transport
async fn Transport::write(self : Transport, data : Bytes) -> Unit {
  match self {
    PlainTcp(tcp) => tcp.write(data)
    TlsConn(tls, _) => tls.write(data)
  }
}

///|
/// Read available bytes from the transport
async fn Transport::read_some(self : Transport) -> Bytes? {
  match self {
    PlainTcp(tcp) => tcp.read_some()
    TlsConn(tls, _) => tls.read_some()
  }
}

///|
/// Close the transport
fn Transport::close(self : Transport) -> Unit {
  match self {
    PlainTcp(tcp) => tcp.close()
    TlsConn(tls, tcp) => {
      tls.close()
      tcp.close()
    }
  }
}
