package immutable;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.MacroStringTools;
using haxe.macro.ExprTools;
using Lambda;

typedef VarMap = Map<String, ComplexType>;

class BuildImmutableClass
{
	/**
	 *  Entry point. Do some basic checks and then iterate all build fields.
	 */
	static function build() {
		// Display mode and vshaxe diagnostics don't need to use this.
		if(Context.defined("display") || Context.defined("display-details")) 
			return null;

		if(Context.defined("disable-immutable") || Context.defined("immutable-disable"))
			return null;

		var ver = Std.parseFloat(Context.getDefines().get('haxe_ver'));
		if(ver < 4) Context.error("Immutable requires Haxe 4.", Context.currentPos());

		var buildFields = Context.getBuildFields();
		
		for(field in buildFields) switch field.kind {
			case FFun(f) if(f.expr != null):
				iterateFunction(new VarMap(), field.name, f);				
			case _:
		}

		return buildFields;
	}

	/**
	 *  Try to get the type from what we know about a var.
	 *  @param currentVars - Currently defined immutable vars
	 *  @param type - Var type hint
	 *  @param value - Var assignment
	 */
	static function typeFromVarData(currentVars : VarMap, type : Null<ComplexType>, value : Null<Expr>) {
		if(type != null) return type;
		if(value == null) return null;

		// Try to convert the value into a type.
		try return Context.toComplexType(Context.typeof(value)) 
		catch(e : Dynamic) {}

		/* 
			Since that failed, replace existing immutable vars with their type, turning:

			macro a.a.map(f -> f.toString())
			into
			macro (null : Array<Date>).map(f -> f.toString())

			The compiler now knows how to resolve the type of this expression!
		*/

		var swapMap = new Map<Expr, ExprDef>();

		function swapIdentifierWithType(e : Expr) switch e.expr {
			// Look for "a.a" expressions that has an existing immutable var.
			case EField({expr: EConst(CIdent(i)), pos: _}, field) if(field == i && currentVars.exists(i)):
				var type = currentVars[i];
				// Save old expr so it can be restored afterwards.
				swapMap.set(e, e.expr);
				e.expr = (macro (null : $type)).expr;
			case _:
				e.iter(swapIdentifierWithType);
		}

		function swapBack() {
			// Restore swapped expressions
			for(e in swapMap.keys()) {
				e.expr = swapMap[e];
			}
		}

		try {
			swapIdentifierWithType(value);
			var type = Context.toComplexType(Context.typeof(value));
			swapBack();
			return type;
		} catch(e : Dynamic) {
			swapBack();
			return null;
		}
	}

	/**
	 *  Determine which arguments are immutable in a function, then inject new immutable vars 
	 *  as a replacement, and parse the rest of the function for local immutable vars.
	 *  @param currentImmutableVars - Currently defined immutable vars
	 *  @param name - Function name
	 *  @param f - The function AST
	 */
	static function iterateFunction(currentImmutableVars : VarMap, name : Null<String>, f : Function) {
		// Make a copy of current immutable vars
		var hasImmutableArgs = false;
		var immutableArgs = [for(key in currentImmutableVars.keys())
			key => currentImmutableVars[key]
		];

		var isProbablyLambda = name == null && switch f.expr.expr {
			case EReturn(e): true;
			case _: false;
		};
		
		for(arg in f.args) {
			if(!isProbablyLambda && (arg.meta == null || !arg.meta.exists(a -> a.name == "mutable"))) {
				// If arg is immutable, add it to the map
				immutableArgs.set(arg.name, typeFromVarData(currentImmutableVars, arg.type, arg.value));
				hasImmutableArgs = true;
			} else {
				// If arg is mutable, remove it from the copy of the
				// current var lists, in case it exists in the outer scope.
				immutableArgs.remove(arg.name);
			}
		}

		replaceVarsWithFinalStructs(immutableArgs, f.expr);
		if(hasImmutableArgs) injectImmutableArgNames(immutableArgs, f);
	}

	/**
	 *  Add a var of the same name as the arg in the beginning of the function, 
	 *  to prevent modifications of the argument.
	 *  @param immutables - Currently defined immutable vars
	 *  @param f - Function AST
	 */
	static function injectImmutableArgNames(immutables : VarMap, f : Function) {
		var newVars = EVars([for(arg in f.args) if(immutables.exists(arg.name)) {
			var name = arg.name;

			var type = typeFromVarData(immutables, arg.type, arg.value);
			if(type == null) Context.error(
				'No type information found, cannot make function argument $name immutable.', f.expr.pos
			);

			{
				name: name,
				type: TAnonymous([{
					access: [AFinal],
					doc: null,
					kind: FVar(type, null),
					meta: null,
					name: name,
					pos: f.expr.pos
				}]),
				expr: {
					expr: EObjectDecl([{
						field: name,
						expr: macro $i{name}
					}]),
					pos: f.expr.pos
				}
			}
		}]);

		var varExpr = { expr: newVars, pos: f.expr.pos };

		switch f.expr.expr {
			case EBlock(exprs):
				exprs.unshift(varExpr);
			case _:
				f.expr = {
					expr: EBlock([varExpr, f.expr]), 
					pos: f.expr.pos
				};
		}
	}

	/**
	 *  Replace local vars with an anonymous structure containing a field that is final.
	 *  
	 *  var a : T = V
	 *  Becomes
	 *  var a : { final a: T; } = {a: V}
	 *  
	 *  And all future references to "a" are changed to "a.a"
	 *  
	 *  @param varMap - Currently defined immutable vars
	 *  @param e - Expression to parse
	 */
	static function replaceVarsWithFinalStructs(varMap : VarMap, e : Expr) switch e.expr {
		case EVars(vars):
			for(v in vars) {
				if(v.expr == null) Context.error(
					'var ${v.name} is immutable and must be assigned immediately.', e.pos
				)
				else {
					replaceVarsWithFinalStructs(varMap, v.expr);
				}

				var name = v.name;
				var type = typeFromVarData(varMap, v.type, v.expr);

				if(type == null) Context.error(
					'No type information found, cannot make var $name immutable.', v.expr.pos
				);

				v.type = TAnonymous([{
					access: [AFinal],
					doc: null,
					kind: FVar(type, null),
					meta: null,
					name: name,
					pos: v.expr.pos
				}]);
				v.expr = {
					expr: EObjectDecl([{
						field: name,
						expr: v.expr
					}]),
					pos: v.expr.pos
				};

				varMap.set(name, type);
			}

		case EConst(CIdent(id)) if(varMap.exists(id)):
			e.expr = (macro $p{[id,id]}).expr;

		case EFunction(name, f):
			iterateFunction(varMap, name, f);

		case EMeta(entry, {expr: EVars(vars), pos: _}) if(entry.name == "mutable"):
			for(v in vars) if(v.expr != null)
				replaceVarsWithFinalStructs(varMap, v.expr);

		case _:
			e.iter(replaceVarsWithFinalStructs.bind(varMap));
	}
}
#end
