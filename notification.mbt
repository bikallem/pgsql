///| LISTEN/NOTIFY Support
///
/// Provides asynchronous notification handling for PostgreSQL channels.

///|
/// An asynchronous notification received from PostgreSQL
struct Notification {
  /// Channel name
  channel : String
  /// Notification payload
  payload : String
  /// Backend process ID of the notifier
  process_id : Int
} derive(Show, Eq)

///|
fn Notification::new(
  channel : String,
  payload : String,
  process_id : Int,
) -> Notification {
  { channel, payload, process_id }
}

///|
/// Channel name
pub fn Notification::channel(self : Notification) -> String {
  self.channel
}

///|
/// Notification payload
pub fn Notification::payload(self : Notification) -> String {
  self.payload
}

///|
/// Backend process ID of the notifier
pub fn Notification::process_id(self : Notification) -> Int {
  self.process_id
}
