import gleam/dict.{type Dict}
import gleam/function
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/string_tree
import mist
import nakai
import nakai/attr
import nakai/html
import wisp

pub fn handle_request(req: wisp.Request) -> wisp.Response {
  use <- wisp.rescue_crashes
  use <- wisp.log_request(req)
  use <- wisp.serve_static(req, under: "/static", from: static_directory())

  case request.path_segments(req) {
    [] -> {
      let board = get_board_from_cookie(req)
      let body: wisp.Body =
        draw_board(board)
        |> nakai.to_string_tree
        |> wisp.Text
      wisp.response(200)
      |> wisp.set_body(body)
    }
    ["move"] -> handle_move(req)
    ["reset"] -> handle_reset(req)
    _ -> wisp.not_found()
  }
}

type GameState {
  Win(Player)
  Tie
  Ongoing
}

fn check_board_win(board: Board) -> GameState {
  let row_indices = [[0, 1, 2], [3, 4, 5], [6, 7, 8]]
  let col_indices = [[0, 3, 6], [1, 4, 7], [2, 5, 8]]
  let diag_indices = [[0, 4, 8], [2, 4, 6]]

  let all_indices =
    list.append(row_indices, col_indices)
    |> list.append(diag_indices)

  let check_win = fn(player: Player, indices: List(Int)) -> Bool {
    indices
    |> list.all(fn(i) {
      case dict.get(board, i) {
        Ok(Occupied(p)) if p == player -> True
        _ -> False
      }
    })
  }

  let check_win = fn(player: Player) -> Bool {
    all_indices
    |> list.map(check_win(player, _))
    |> list.any(function.identity)
  }

  case check_win(X), check_win(O) {
    True, _ -> Win(X)
    _, True -> Win(O)
    _, _ -> {
      case check_full(board) {
        True -> Tie
        False -> Ongoing
      }
    }
  }
}

fn check_full(board: Board) -> Bool {
  list.range(0, 8)
  |> list.all(fn(index) {
    case dict.get(board, index) {
      Ok(Occupied(_)) -> True
      _ -> False
    }
  })
}

fn make_cell_from_form_cell(form_value: String) -> Cell {
  case form_value {
    "X" -> Occupied(X)
    "O" -> Occupied(O)
    _ -> Empty
  }
}

fn handle_reset(req: wisp.Request) -> wisp.Response {
  wisp.redirect("/")
  |> wisp.set_cookie(req, "board", ".........", wisp.PlainText, 99_999)
}

fn handle_move(req: wisp.Request) -> wisp.Response {
  use form <- wisp.require_form(req)
  let board = get_board_from_cookie(req)
  let next_player = infer_player(board)

  let assert [#(cell_id, cell_value)] = form.values

  let current_cell = make_cell_from_form_cell(cell_value)
  case current_cell {
    Occupied(_) -> wisp.redirect("/")
    Empty -> {
      let assert Ok(index_to_move) = int.parse(cell_id)
      let new_board = dict.insert(board, index_to_move, Occupied(next_player))
      wisp.redirect("/")
      |> wisp.set_cookie(
        req,
        "board",
        board_to_string(new_board),
        wisp.PlainText,
        99_999,
      )
    }
  }
}

pub type Cell {
  Occupied(Player)
  Empty
}

pub type Player {
  X
  O
}

pub type Board =
  Dict(Int, Cell)

fn board_to_string(board: Dict(Int, Cell)) -> String {
  list.range(0, 8)
  |> list.fold("", fn(acc, index) {
    let value_of_board = case dict.get(board, index) {
      Ok(cell) -> cell
      Error(Nil) -> Empty
    }
    case value_of_board {
      Occupied(X) -> acc <> "X"
      Occupied(O) -> acc <> "O"
      Empty -> acc <> "."
    }
  })
}

fn get_board_from_cookie(req: wisp.Request) -> Dict(Int, Cell) {
  let cookie = wisp.get_cookie(req, "board", wisp.PlainText)
  let board_string = result.unwrap(cookie, ".........")
  let board_list = string.split(board_string, "")

  list.index_fold(
    board_list,
    dict.new(),
    fn(acc: Dict(Int, Cell), item: String, index: Int) {
      let cell: Cell = case item {
        "X" -> Occupied(X)
        "O" -> Occupied(O)
        "." -> Empty
        _ -> Empty
      }
      dict.insert(acc, index, cell)
    },
  )
}

fn infer_player(board: Dict(Int, Cell)) -> Player {
  let count_moves =
    dict.fold(board, 0, fn(acc, key, value) {
      case value {
        Occupied(_) -> acc + 1
        Empty -> acc
      }
    })

  let mod_result = count_moves % 2
  case mod_result {
    0 -> X
    _ -> O
  }
}

fn static_directory() {
  let assert Ok(priv_directory) = wisp.priv_directory("hello_gleam")
  priv_directory <> "/static"
}

pub fn draw_board(board: Board) -> html.Node {
  let make_cell = fn(cell_id: String, cell_value: String) {
    html.form([attr.action("/move"), attr.method("post")], [
      html.input([
        attr.class("board-cell"),
        attr.type_("submit"),
        attr.name(cell_id),
        attr.value(cell_value),
      ]),
    ])
  }
  let board_cells =
    list.range(0, 8)
    |> list.map(fn(index) {
      let cell = dict.get(board, index) |> result.unwrap(Empty)
      let cell_str = case cell {
        Occupied(X) -> "X"
        Occupied(O) -> "O"
        Empty -> " "
      }
      int.to_string(index)
      |> make_cell(cell_str)
    })

  let board = html.div([attr.class("board")], board_cells)

  let reset =
    html.form([attr.action("/reset"), attr.method("post")], [
      html.input([
        attr.class("reset-button"),
        attr.type_("submit"),
        attr.name("reset"),
        attr.value("Reset Game"),
      ]),
    ])

  //     let reset_button = html.form([],
  //     [html.input([attr.id("reset-button")], "Reset Game")])
  //   let reset = html.button_text([attr.id("reset-button")], "Reset Game")

  html_scaffolding([board, reset])
}

fn html_scaffolding(body: List(html.Node)) -> html.Node {
  let stylesheet_link =
    html.link([attr.rel("stylesheet"), attr.href("static/styles.css")])

  html.Html([attr.lang("en-CA")], [
    html.Head([stylesheet_link]),
    html.Body([], body),
  ])
}
