package immutable;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.MacroStringTools;
using haxe.macro.ExprTools;
using haxe.macro.TypedExprTools;

using Lambda;
using StringTools;

typedef VarMap = Map<String, ComplexType>;

class BuildImmutableClass
{
	static function build() {
		if(Context.defined("display")) return null;

		var ver = Std.parseFloat(Context.getDefines().get('haxe_ver'));
		if(ver < 4) Context.error("Immutable requires Haxe 4.", Context.currentPos());

		if(Context.defined("disable-immutable") || Context.defined("immutable-disable"))
			return null;

		var cls : ClassType = Context.getLocalClass().get();
		var buildFields = Context.getBuildFields();
		
		for(field in buildFields) switch field.kind {
			case FFun(f) if(f.expr != null):
				iterateFunction(new VarMap(), field.name, f);				
			case _:
		}

		return buildFields;
	}

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
		if(hasImmutableArgs) injectImmutableVarNames(immutableArgs, f);
	}

	static function injectImmutableVarNames(immutables : VarMap, f : Function) {
		//trace([for(m in mutables.keys()) m]);
		// Add a var of the same name as the arg in the beginning of the function.
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

				// var a : T = V    
				// Becomes
				// var a : { final a: T; } = {a: V}

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
			for(v in vars) 
				replaceVarsWithFinalStructs(varMap, v.expr);

		case _:
			//trace(e.expr);
			e.iter(replaceVarsWithFinalStructs.bind(varMap));
	}
}
#end
