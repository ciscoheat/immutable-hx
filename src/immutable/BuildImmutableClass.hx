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

class BuildImmutableClass
{
	static function build() {
		var ver = Std.parseFloat(Context.getDefines().get('haxe_ver'));
		if(ver < 4) Context.error("Immutable requires Haxe 4.", Context.currentPos());

		if(Context.defined("disable-immutable") || Context.defined("immutable-disable"))
			return null;

		var cls : ClassType = Context.getLocalClass().get();
		var buildFields = Context.getBuildFields();
		
		// Remove some optimizations to avoid mutable vars being modified by the compiler
		//cls.meta.add(":analyzer", [macro no_local_dce], cls.pos);
		//if(Context.defined("display")) return null;

		for(field in buildFields) switch field.kind {
			case FFun(f) if(f.expr != null):
				iterateFunction(new Map<String, Bool>(), f);
			case _:
		}

		return buildFields;
	}

	static function iterateFunction(currentImmutableVars : Map<String, Bool>, f : Function) {
		// Make a copy of current immutable vars
		var immutableArgs = [for(key in currentImmutableVars.keys())
			key => true
		];
		var mutableArgs = new Map<String, Bool>(); 
		var hasImmutableArgs = false;
		
		for(arg in f.args) {
			if(arg.meta == null || !arg.meta.exists(a -> a.name == "mutable")) {
				// If arg is immutable, add it to the map
				immutableArgs.set(arg.name, true);
				hasImmutableArgs = true;
			} else {
				// If arg is mutable, remove it from the copy of the
				// current var lists, in case it exists in the outer scope.
				mutableArgs.set(arg.name, true);
				immutableArgs.remove(arg.name);
			}
		}

		replaceVarsWithFinalStructs(immutableArgs, f.expr);
		if(hasImmutableArgs) injectImmutableVarNames(mutableArgs, f);
	}

	static function injectImmutableVarNames(mutables : Map<String, Bool>, f : Function) {
		//trace([for(m in mutables.keys()) m]);
		// Add a var of the same name as the arg in the beginning of the function.
		var newVars = EVars([for(arg in f.args) if(!mutables.exists(arg.name)) {
			name: arg.name,
			type: TAnonymous([{
				access: [AFinal],
				doc: null,
				kind: FVar(arg.type, null),
				meta: null,
				name: arg.name,
				pos: f.expr.pos
			}]),
			expr: {
				expr: EObjectDecl([{
					field: arg.name,
					expr: macro $i{arg.name}
				}]),
				pos: f.expr.pos
			}
		}]);

		//trace("Immutable vars:"); trace(newVars); trace("-----------------");

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

	static function replaceVarsWithFinalStructs(varMap : Map<String, Bool>, e : Expr) switch e.expr {
		case EVars(vars):
			for(v in vars) {
				if(v.expr == null) Context.error(
					'var ${v.name} is immutable and must be assigned immediately.', e.pos
				)
				else {
					replaceVarsWithFinalStructs(varMap, v.expr);
				}

				var name = v.name;

				var type = try {
					if(v.type != null) v.type 
					else Context.toComplexType(Context.typeof(v.expr));
				}
				catch(e : Dynamic) Context.error(
					'No type information found, cannot make var $name immutable.', 
					v.expr.pos
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

				varMap.set(name, true);
			}

		case EConst(CIdent(i)) if(varMap.exists(i)):
			e.expr = (macro $p{[i,i]}).expr;

		case EFunction(name, f):
			iterateFunction(varMap, f);

		case EMeta(entry, {expr: EVars(vars), pos: _}) if(entry.name == "mutable"):
			for(v in vars) 
				replaceVarsWithFinalStructs(varMap, v.expr);

		case _:
			//trace(e.expr);
			e.iter(replaceVarsWithFinalStructs.bind(varMap));
	}
}
#end
