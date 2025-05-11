import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/io
import mist
import ttt
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  let secret_key = wisp.random_string(64)
  let assert Ok(_) =
    wisp_mist.handler(ttt.handle_request, secret_key)
    |> mist.new
    |> mist.port(3030)
    |> mist.start_http

  process.sleep_forever()
}

fn handle_request(
  req: request.Request(mist.Connection),
) -> response.Response(mist.ResponseData) {
  case request.path_segments(req) {
    [] -> html_response("<h1>Esme says Hello!</h1>")
    ["chai"] -> html_response("<h1>Chai says Hello!</h1>")
    ["chai" <> extra] ->
      html_response("<h1> Chai says hello and " <> extra <> "</h1>")
    _ -> not_found_response()
  }
}

fn not_found_response() -> response.Response(mist.ResponseData) {
  let empty_body = mist.Bytes(bytes_tree.new())
  response.new(404)
  |> response.set_body(empty_body)
}

fn html_response(html_text: String) -> response.Response(mist.ResponseData) {
  let body = html_text |> bytes_tree.from_string |> mist.Bytes

  response.new(200)
  |> response.set_header("Content-Type", "text/html")
  |> response.set_body(body)
}
