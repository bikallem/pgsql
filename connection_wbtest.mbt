///|
test "NotificationQueue dequeues in FIFO order" {
  let queue = NotificationQueue::new()
  queue.enqueue(Notification::new("a", "payload-a", 1))
  queue.enqueue(Notification::new("b", "payload-b", 2))
  queue.enqueue(Notification::new("c", "payload-c", 3))

  match queue.dequeue() {
    Some(notification) => {
      assert_eq(notification.channel(), "a")
      assert_eq(notification.payload(), "payload-a")
      assert_eq(notification.process_id(), 1)
    }
    None => fail("Expected first queued notification")
  }

  match queue.dequeue() {
    Some(notification) => {
      assert_eq(notification.channel(), "b")
      assert_eq(notification.payload(), "payload-b")
      assert_eq(notification.process_id(), 2)
    }
    None => fail("Expected second queued notification")
  }

  match queue.dequeue() {
    Some(notification) => {
      assert_eq(notification.channel(), "c")
      assert_eq(notification.payload(), "payload-c")
      assert_eq(notification.process_id(), 3)
    }
    None => fail("Expected third queued notification")
  }

  match queue.dequeue() {
    None => ()
    Some(_) => fail("Expected empty queue after all dequeues")
  }
}

///|
test "NotificationQueue stays ordered under high volume" {
  let queue = NotificationQueue::new()
  let total = 3000
  let consumed = 2500

  for i = 0; i < total; i = i + 1 {
    queue.enqueue(Notification::new("bulk", i.to_string(), i))
  }

  for i = 0; i < consumed; i = i + 1 {
    match queue.dequeue() {
      Some(notification) => {
        assert_eq(notification.process_id(), i)
        assert_eq(notification.payload(), i.to_string())
      }
      None => fail("Expected queued notification during high-volume dequeue")
    }
  }

  let remaining = queue.drain()
  assert_eq(remaining.length(), total - consumed)
  for i, notification in remaining {
    assert_eq(notification.process_id(), consumed + i)
    assert_eq(notification.payload(), (consumed + i).to_string())
  }

  match queue.dequeue() {
    None => ()
    Some(_) => fail("Expected queue to be empty after drain")
  }
}

///|
test "NotificationQueue empty dequeue returns None" {
  let queue = NotificationQueue::new()
  inspect(queue.dequeue(), content="None")
  inspect(queue.dequeue(), content="None") // idempotent
}

///|
test "NotificationQueue empty drain returns empty array" {
  let queue = NotificationQueue::new()
  inspect(queue.drain().length(), content="0")
  inspect(queue.drain().length(), content="0") // idempotent
}

///|
test "NotificationQueue drain with head at zero copies all" {
  let queue = NotificationQueue::new()
  queue.enqueue(Notification::new("x", "1", 1))
  queue.enqueue(Notification::new("y", "2", 2))
  let result = queue.drain()
  assert_eq(result.length(), 2)
  assert_eq(result[0].channel(), "x")
  assert_eq(result[1].channel(), "y")
  // Queue should be empty after drain
  inspect(queue.dequeue(), content="None")
}

///|
test "NotificationQueue drain with nonzero head returns remaining" {
  let queue = NotificationQueue::new()
  queue.enqueue(Notification::new("a", "1", 1))
  queue.enqueue(Notification::new("b", "2", 2))
  queue.enqueue(Notification::new("c", "3", 3))
  // Consume first item, advancing head
  ignore((queue.dequeue() : Notification?))
  let result = queue.drain()
  assert_eq(result.length(), 2)
  assert_eq(result[0].channel(), "b")
  assert_eq(result[1].channel(), "c")
  inspect(queue.dequeue(), content="None")
}

///|
test "NotificationQueue compact preserves ordering" {
  let queue = NotificationQueue::new()
  // Enqueue enough to trigger compaction (head >= 128 and head*2 >= len)
  for i = 0; i < 300; i = i + 1 {
    queue.enqueue(Notification::new("ch", i.to_string(), i))
  }
  // Dequeue 200 items, leaving 100 with head=200
  // head=200 >= 128 and 200*2=400 >= 300, so compaction will trigger
  for i = 0; i < 200; i = i + 1 {
    match queue.dequeue() {
      Some(n) => assert_eq(n.process_id(), i)
      None => fail("Expected notification at index " + i.to_string())
    }
  }
  // Remaining 100 should be preserved in order
  for i = 200; i < 300; i = i + 1 {
    match queue.dequeue() {
      Some(n) => assert_eq(n.process_id(), i)
      None => fail("Expected notification at index " + i.to_string())
    }
  }
  inspect(queue.dequeue(), content="None")
}

///|
test "encode_frontend_batch matches concatenated protocol encoding" {
  let msgs : Array[FrontendMessage] = [
    Query("SELECT 1"),
    Sync,
  ]
  let batch = encode_frontend_batch(msgs)

  let expected : Array[Byte] = []
  for msg in msgs {
    let encoded = encode(msg)
    for i = 0; i < encoded.length(); i = i + 1 {
      expected.push(encoded[i])
    }
  }

  assert_eq(batch.length(), expected.length())
  for i = 0; i < batch.length(); i = i + 1 {
    assert_eq(batch[i], expected[i])
  }
}

///|
test "encode_frontend_batch passes through single message encoding" {
  let msg = Flush
  let batch = encode_frontend_batch([msg])
  let encoded = encode(msg)
  assert_eq(batch.length(), encoded.length())
  for i = 0; i < batch.length(); i = i + 1 {
    assert_eq(batch[i], encoded[i])
  }
}
