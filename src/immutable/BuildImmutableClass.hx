package immutable;
import haxe.PosInfos;
import haxe.macro.Format;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.MacroStringTools;
using haxe.macro.ExprTools;
using haxe.macro.TypedExprTools;

using Lambda;
using StringTools;

private enum Mutable {
	WholeScope;
	NextExpr;
}

class BuildImmutableClass
{
	static var immutableTypes = new Map<String, BuildImmutableClass>();
	static var typesChecked = false;
	static var globalAssignmentErrors = new Array<{error: String, pos: Position}>();
	
	static function build(onlyLocalVars : Bool) {
		var cls : ClassType = Context.getLocalClass().get();
		var buildFields = Context.getBuildFields();
		
		if (Context.defined("disable-immutable")) return null;

		// Remove some optimizations to avoid mutable vars being modified by the compiler
		cls.meta.add(":analyzer", [macro no_local_dce], cls.pos);
		
		var fieldNames = [for (field in buildFields) field.name];
		var mutableFieldNames = [];
		for (field in buildFields) {
			if (field.meta.find(function(m) return m.name == "mutable") != null) {
				Context.warning('Field ${field.name} marked as mutable in immutable class', field.pos);
				mutableFieldNames.push(field.name);
			}
		}
		
		var className = cls.pack.toDotPath(cls.name);
		var builder = new BuildImmutableClass(className, fieldNames, mutableFieldNames, onlyLocalVars);
		
		if(!Context.defined("display")) {
			immutableTypes.set(className, builder);

			Context.onGenerate(function(types) {
				if (typesChecked) return;
				typesChecked = true;
				
				for (type in types) switch type {
					case TInst(t, _):
						var inst = t.get();
						var typeName = inst.pack.toDotPath(inst.name);
						if (immutableTypes.exists(typeName)) {
							
							var meta = inst.meta.get();
							
							var localDce = meta.find(function(m)
								return m.name == ":analyzer" && 
									m.params.length > 0 &&
									m.params[0].expr.equals(EConst(CIdent("local_dce")))
							);
							
							if (localDce != null) Context.warning(
								"Using @:analyzer(local_dce) can give unpredictable behavior on an Immutable class.",
							inst.pos);

							var allClassFields = inst.fields.get()
								.concat(inst.statics.get())								
								.concat(inst.overrides.map(function(i) return i.get()));
								
							if (inst.constructor != null) allClassFields.push(inst.constructor.get());

							var builder = immutableTypes.get(typeName);
							
							for (field in allClassFields) {
								if(!builder.onlyLocalVars) switch field.kind {
									case FVar(_, write):
										if (field.isPublic && write != AccNo && write != AccNever && !builder.mutableFieldNames.has(field.name)) {
											globalAssignmentErrors.push({
												error: "Setters are not allowed in an Immutable class. Use only 'null' or 'never'.", 
												pos: field.pos
											});
										}
									case FMethod(k):
										if (k == MethDynamic) globalAssignmentErrors.push({
											error: "Dynamic methods aren't allowed in an Immutable class.", 
											pos: field.pos
										});
								}
								
								if (field.expr() != null) {									
									builder.preventAssignments(field.name == "new", field.expr());
								}
							}
							
							for (p in builder.assignmentErrors) globalAssignmentErrors.push({
								error: "Cannot make assignments in an immutable class without marking the var with @mutable.",
								pos: p
							});
						}
					case _:
				}
				
				if (globalAssignmentErrors.length > 0) {
					globalAssignmentErrors.sort(function(a, b) return Std.string(a) < Std.string(b) ? 1 : -1);
					
					for (error in globalAssignmentErrors.slice(0, -1))
						Context.warning(error.error, error.pos);
						
					var lastError = globalAssignmentErrors[globalAssignmentErrors.length - 1];						
					Context.error(lastError.error, lastError.pos);
				}				
			});
		}

		return builder.makeImmutable(buildFields);
	}
	
	//////////////////////////////////////////////////////////////////////////

	public var assignmentErrors(default, null) = new Array<Position>();

	var className : String;
	var fieldNames : Array<String>;
	var mutableFieldNames : Array<String>;
	
	var onlyLocalVars : Bool;
	
	function new(className, fieldNames, mutableFieldNames, onlyLocalVars) {
		this.className = className;
		this.fieldNames = fieldNames;
		this.mutableFieldNames = mutableFieldNames;
		this.onlyLocalVars = onlyLocalVars;
	}
	
	function makeImmutable(fields : Array<Field>) : Array<Field> {
		return fields.map(function(field) return switch field.kind {
			case FVar(t, e):
				if (e != null) renameMutableVars(false, new Map<String, Mutable>(), e);
				
				// Rewrite public vars to var(default, null)
				if(field.access.has(APublic) && !onlyLocalVars && !mutableFieldNames.has(field.name))
					field.kind = FProp('default', 'null', t, e);
					
				field;
			
			case FProp(get, set, t, e):
				if (e != null) renameMutableVars(false, new Map<String, Mutable>(), e);
				field;
				
			case FFun(f):
				// Test if some method arguments are marked with mutable
				var mutables = new Map<String, Mutable>();
				for (arg in mutableFunctionArguments(f.args)) mutables.set(arg, WholeScope);
				
				if (f.expr != null) renameMutableVars(field.name == "new", mutables, f.expr);
				field;
		});		
	}
	
	// NOTE: Also modifies the argument name, if @mutable
	function mutableFunctionArguments(args : Array<FunctionArg>) : Array<String> {
		#if (haxe_ver >= 3.3)
		return [for (arg in args) {
			if (arg.meta.exists(function(m) return m.name == "mutable")) {
				var originalName = arg.name;
				arg.name = mutableVarName(arg.name);
				originalName;		
			}
		}];
		#else
		return [];
		#end
	}
	
	function mutableVarName(name : String) return '__hxim__' + name;
	function mutableIfVarName(name : String) return '__hxim_ex_' + name;
	
	function cloneMap(mutables : Map<String, Mutable>) {
		var newMutableScope = new Map<String, Mutable>();
		for (key in mutables.keys()) newMutableScope.set(key, mutables.get(key));
		return newMutableScope;
	}
	
	function renameMutableVars(inConstructor : Bool, mutables : Map<String, Mutable>, e : Expr) {
		switch e.expr {
			case EBlock(exprs):
				// New block, create a new scope for mutable vars
				var newMutableScope = cloneMap(mutables);
				for (e2 in exprs) renameMutableVars(inConstructor, newMutableScope, e2);
				return;
			
			case EFunction(_, f) if(f.expr != null):
				var newMutableScope = cloneMap(mutables);
				for (key in mutableFunctionArguments(f.args)) newMutableScope.set(key, WholeScope);				
				renameMutableVars(inConstructor, newMutableScope, f.expr);
				return;
				
			case EVars(vars):
				// New vars, remove mutables in the current scope if they exist
				for (v in vars) {
					mutables.remove(v.name);
					// Test for complex assignments. The compiler can modify these,
					// so they need to be tested separately in the typed phase.
					if (v.expr != null) switch v.expr.expr {
						case EIf(_, _, _) | ESwitch(_, _, _) | ETry(_, _): // | EParenthesis(_):
							mutables.set(v.name, NextExpr);
							v.name = mutableIfVarName(v.name);
						// Check one level of parenthesis only.
						case EParenthesis(e): switch e.expr {
							case EIf(_, _, _) | ESwitch(_, _, _) | ETry(_, _):
								mutables.set(v.name, NextExpr);
								v.name = mutableIfVarName(v.name);
							case _:
						}
							
						case _:
					}
				}
				
			case EConst(CString(s)) if (e.toString().startsWith("'")):
				// Rename vars in interpolated strings
				e.expr = Format.format(e).expr;
				renameMutableVars(inConstructor, mutables, e);
				return;
				
			case EConst(CIdent(s)):
				e.expr = switch mutables.get(s) {
					case WholeScope: EConst(CIdent(mutableVarName(s)));
					case NextExpr: EConst(CIdent(mutableIfVarName(s)));
					case _: e.expr;
				}
				
			case EMeta(s, { expr: EVars(vars), pos: _ }) if (s.name == "mutable"):
				// Run through the vars expressions separately, to avoid them being immutable in the EVars switch.
				// Run them before setting mutables, because the var expressions aren't in that scope.
				for (v in vars) if(v.expr != null) renameMutableVars(inConstructor, mutables, v.expr);
				
				// Set mutables for the current scope and rename the var so it can be identified as mutable.
				for (v in vars) if (!mutables.exists(v.name)) {
					mutables.set(v.name, WholeScope);
					v.name = mutableVarName(v.name);
				}
				
				// Need to remove the meta, otherwise it won't compile
				e.expr = EVars(vars);
				return;
				
			case _: 
		}
		
		e.iter(renameMutableVars.bind(inConstructor, mutables));
	}
	
	function typedAssignmentError(e : TypedExpr, ?pos : PosInfos) {
		//trace("===== Assignment error ====="); trace(pos); trace(e.expr); trace(e.t);
		assignmentErrors.push(e.pos);
	}
	
	var safeLocals = new Map<Int, Bool>();
	var unassignedLocals = new Map<Int, Bool>();
	
	function preventAssignments(inConstructor : Bool, e : TypedExpr) {
		function failIfNotMap(t : ClassType) {
			var mapType = ~/^haxe\.ds\.[A-Z]\w+Map$/;
			
			if (!mapType.match(t.pack.toDotPath(t.name)))
				typedAssignmentError(e);
		}
		
		switch e.expr {
			case TBlock(el):
				var safeLocalInNextExpression = 0;
				var checkForVarInNextExpr : String = null;
				
				function setSafeInNextExpr(v, check : String = null) {
					safeLocals.set(v.id, true);
					safeLocalInNextExpression = v.id;
					checkForVarInNextExpr = check;
				}
				
				for (texpr in el) {	
					// Test if the expression is a complex assignment, then set the var as safe 
					// for the next expression, which the compiler may have rewritten.
					switch texpr.expr {
						case TVar(v, vexpr):
							// A normal, empty var, so one assignment is allowed.
							if (vexpr == null && !v.name.startsWith("__hxim_ex_")) {
								unassignedLocals.set(v.id, true);
							}
							
							// Neko Map vars, will contain __id__, so check for that
							if (vexpr == null && v.name.startsWith("id")) {
								setSafeInNextExpr(v, "__id__");
							}
							// Complex assignment vars (var a == if(...))
							else if (v.name.startsWith("__hxim_ex_")) {
								setSafeInNextExpr(v);
							}
							// Iterator for haxe.xml.Fast
							else if (~/^_g\d*_head\d*$/.match(v.name)) {
								setSafeInNextExpr(v);
							}
							// _g\d* is a For -> While loop iterator
							else if (~/^_g\d*$/.match(v.name) && vexpr.expr.equals(TConst(TInt(0)))) {
								setSafeInNextExpr(v);
							} 
							else {
								//trace(v.name); trace(vexpr);
								preventAssignments(inConstructor, texpr);
							}							
							continue;
							
						case _: 
					}

					// Test if a variable uses another var, like __id__ for compiler generated expressions.
					if (checkForVarInNextExpr != null) {
						var hasVar = false;
						function findVar(t : TypedExpr) {
							switch t.expr {
								case TField(_, fa) if (fa.equals(FDynamic(checkForVarInNextExpr))): hasVar = true;
								case _: if (!hasVar) t.iter(findVar);
							}
						}
						findVar(texpr);
						if (!hasVar) typedAssignmentError(texpr);
					}

					preventAssignments(inConstructor, texpr);
						
					// If current expression is a non-var expression, clear "checkForVar".
					if (safeLocalInNextExpression > 0) {
						safeLocals.remove(safeLocalInNextExpression);
						safeLocalInNextExpression = 0;
						checkForVarInNextExpr = null;
					}					
				}
								
				return;

			case TBinop(OpAssign, e1, _) | TBinop(OpAssignOp(_), e1, _) | TUnop(OpIncrement, _, e1) | TUnop(OpDecrement, _, e1) : switch(e1.expr) {

				case TLocal(v):
					if (safeLocals.exists(v.id)) {
						return;
					}
					else if (unassignedLocals.exists(v.id)) {
						unassignedLocals.remove(v.id);
						return;
					}
					
					// Very bizarre case, some Map.set are abstracted as
					// an assignment that must be picked apart.
					switch e1.expr {
						case TField( { expr: TLocal(v2), t: t, pos: _ }, fa):
							// Additional set may create id1, id2, ...
							if (v.name.startsWith("id") && fa.equals(FDynamic("__id__"))) {
								// Confirmed a Map.set statement, so set its var as safe,
								// in case it appears in a later statement.
								safeLocals.set(v.id, true);
								return;
							}
						case _: 							
					}
					
					// _g\d+ is a special for loop comprehension field
					if (!v.name.startsWith("__hxim__") && !~/^_g\d*$/.match(v.name)) {
						if (!Reflect.hasField(v, "meta")) return typedAssignmentError(e1);
			
						// The compiler can generate assignments, trust them for now.
						#if (haxe_ver < 3.3)
						var meta : Array<Dynamic> = untyped v.meta;
						#else
						// Working properly in 3.3
						var meta = v.meta.get();
						#end
						if (!meta.exists(function(m) return m.name == ":compilerGenerated"))
							typedAssignmentError(e1);
					}

				case TField({ expr: fieldExpr, t: t, pos: _ }, fa): 
					var skipClassFieldTests = if(onlyLocalVars) true else switch t {
						// Skip instance references not pointing to the own class
						case TInst(clsType, _) if (clsType.get().pack.toDotPath(clsType.get().name) != className):
							true;
						
						// Skip type references not of the same class
						case TType(defType, _):
							var name = defType.get().name;
							var extract = ~/^Class<(.*)>$/;

							if (extract.match(name)) {
								defType.get().pack.toDotPath(extract.matched(1)) != className;
							} 
							else true;
						
						case _:
							false;
					}
					
					if (!skipClassFieldTests) switch fieldExpr {
						
						// Testing instance field ("this") assignments
						case TConst(TThis):
							switch fa {
								case FInstance(_, _, cf):
									var field = cf.get().name;
									if (!mutableFieldNames.has(field) && !(inConstructor && fieldNames.has(field)))
										typedAssignmentError(e1);
									
								case _: 
									typedAssignmentError(e1);
							}
							
						// Testing static field assignments
						case TTypeExpr(_):
							switch fa {
								case FStatic(_, cf):
									var field = cf.get().name;
									if (!mutableFieldNames.has(field)) typedAssignmentError(e1);
								case _:
									typedAssignmentError(e1);
							}
						
						// Class fields captured by closures. _g1, _g2this, ...
						case TLocal(v) if (v.capture == true && ~/^_g\d*(?:this)?$/.match(v.name)):
						case TLocal(v) if (v.name.startsWith("__hxim__")):
							
						case _:							
							typedAssignmentError(e1);
					}
					
				// Test for generic Map.set, for example StringMap
				// since it's abstract, the set method is replaced by an assignment.
				case TArray( { expr: TField(e3, _), t: t, pos:_ }, _):
					var type = e3.expr.equals(TConst(TThis)) ? t : e3.t;
					switch type {
						case TInst(t2, _): failIfNotMap(t2.get());
						case _: typedAssignmentError(e1);
					}
				
				// Map and Reflect operations on some targets
				case TArray( { expr: TLocal(v), t: t, pos: _ }, _):
					if (!v.name.startsWith("__hxim__")) switch t {
						case TInst(t2, _): failIfNotMap(t2.get());
						case _: typedAssignmentError(e1);
					}
					
				case _: 
					typedAssignmentError(e1);
			}				
			case _: 
		}
		
		e.iter(preventAssignments.bind(inConstructor));
	}	
}
#end
