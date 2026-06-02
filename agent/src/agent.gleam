import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response, new, set_body}
import mist.{type Connection, type ResponseData, Bytes}

pub fn main() {
  let assert Ok(_) =
    mist.new(handle_request)
    |> mist.bind("127.0.0.1")
    |> mist.port(3000)
    |> mist.start()

  process.sleep_forever()
}

fn handle_request(_req: Request(Connection)) -> Response(ResponseData) {
  new(200) |> set_body(Bytes(bytes_tree.from_string("OK")))
}
