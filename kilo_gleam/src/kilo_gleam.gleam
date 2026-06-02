import gleam/io

@external(erlang, "io", "get_chars")
fn erl_get_chars(prompt: String, count: Int) -> String

pub fn main() {
  io.print("raw mode activated. press 'q' to quit.\r\n")
  read_loop()
}

fn read_loop() {
  let char_input = erl_get_chars("", 1)
  case char_input {
    "q" -> {
      io.print("quitting...\r\n")
    }
    _ -> {
      io.print("keypress: " <> char_input <> "\r\n")
      read_loop()
    }
  }
}