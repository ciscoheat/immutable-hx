import haxe.macro.Expr;

class Macro {
  public static macro function assign(v: Expr, ex: Expr) {
    return macro $v = $ex;
  }
}