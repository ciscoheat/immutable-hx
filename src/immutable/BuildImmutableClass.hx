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
	static var immutableTypes = new Map<String, BuildImmutableClass>();
	static var typesChecked = false;
	
	static function build(onlyLocalVars : Bool) {
		var cls : ClassType = Context.getLocalClass().get();
		var buildFields = Context.getBuildFields();
		
		// Remove some optimizations to avoid mutable vars being modified by the compiler
		cls.meta.add(":analyzer", [macro no_local_dce], cls.pos);
		
		var fieldNames = [for (field in buildFields) field.name];
		var mutableFieldNames = [for (field in buildFields) 
			if (field.meta.find(function(m) return m.name == "mutable") != null) {
				Context.warning('Field ${field.name} marked as mutable in immutable class', field.pos);
				field.name;
			}
		];
		
		var className = cls.pack.toDotPath(cls.name);
		var builder = new BuildImmutableClass(className, fieldNames, mutableFieldNames, onlyLocalVars);
		
		if(!Context.defined("display")) {
			immutableTypes.set(className, builder);

			Context.onGenerate(function(types) {
				if (typesChecked) return;
				typesChecked = true;
				
				var assignmentErrors = [];

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
										if (write != AccNo && write != AccNever && !builder.mutableFieldNames.has(field.name)) {
											Context.error(
												"Setters are not allowed in an Immutable class. Use only 'null' or 'never'.", 
											field.pos);
										}
									case FMethod(k):
										if (k == MethDynamic) Context.error(
											"Dynamic methods aren't allowed in an Immutable class.", 
										field.pos);
								}
								
								if (field.expr() != null) {									
									builder.preventAssignments(field.name == "new", field.expr());
								}
							}
							
							for (p in builder.assignmentErrors) assignmentErrors.push(p);							
						}
					case _:
				}
				
				if (assignmentErrors.length > 0) {
					var errorMessage = "Cannot make assignments in an immutable class without marking the var with @mutable.";
					
					assignmentErrors.sort(function(a, b) return Std.string(a) < Std.string(b) ? 1 : -1);
					
					for (pos in assignmentErrors.slice(0, -1))
						Context.warning(errorMessage, pos);
						
					Context.error(errorMessage, assignmentErrors[assignmentErrors.length-1]);
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
				if (e != null) renameMutableVars(false, [], e);
				
				// Rewrite var to var(default, null)
				if(!onlyLocalVars && !mutableFieldNames.has(field.name))
					field.kind = FProp('default', 'null', t, e);
					
				field;
			
			case FProp(get, set, t, e):
				if (e != null) renameMutableVars(false, [], e);
				field;
				
			case FFun(f):
				// Test if some method arguments are marked with mutable
				var mutables = mutableFunctionArguments(f.args);
				if (f.expr != null) renameMutableVars(field.name == "new", mutables, f.expr);
				field;
		});		
	}
	
	// NOTE: Also modifies the argument name, if @mutable
	function mutableFunctionArguments(args : Array<FunctionArg>) : Array<String> {
		return [for (arg in args) {
			if (arg.meta.exists(function(m) return m.name == "mutable")) {
				var originalName = arg.name;
				arg.name = '__mutable_' + arg.name;
				originalName;		
			}
		}];		
	}
	
	function renameMutableVars(inConstructor : Bool, mutables : Array<String>, e : Expr) {
		switch e.expr {
			// New block, create a new scope for mutable vars
			case EBlock(exprs):
				var newMutableScope = mutables.copy();
				for (e2 in exprs) renameMutableVars(inConstructor, newMutableScope, e2);
				return;
			
			case EFunction(_, f):
				if (f.expr != null) renameMutableVars(
					inConstructor, 
					mutables.concat(mutableFunctionArguments(f.args)), 
					f.expr
				);
				return;
				
			// New vars, remove mutables in the current scope if they exist
			case EVars(vars):
				for (v in vars) mutables.remove(v.name);
				
			case EConst(CIdent(s)) if(mutables.has(s)): 
				e.expr = EConst(CIdent('__mutable_$s'));
				
			case EMeta(s, { expr: EVars(vars), pos: _ }) if (s.name == "mutable"):
				// Run through the vars expressions separately, to avoid them being immutable in the EVars switch.
				// Run them before setting mutables, because the var expressions aren't in that scope.
				for (v in vars) renameMutableVars(inConstructor, mutables, v.expr);
				
				// Set mutables for the current scope and rename the var so
				// it can be identified as mutable.
				for (v in vars) if (!mutables.has(v.name)) {
					mutables.push(v.name);
					v.name = '__mutable_${v.name}';
				}
				
				// Need to remove the meta, otherwise it won't compile
				e.expr = EVars(vars);
				return;
				
			case _: 
		}
		
		e.iter(renameMutableVars.bind(inConstructor, mutables));
	}
	
	function typedAssignmentError(e : TypedExpr) {
		//trace("============ error"); trace(e.expr); trace(e.t);
		assignmentErrors.push(e.pos);
	}
	
	var safeLocals = new Map<Int, Bool>();
	
	function preventAssignments(inConstructor : Bool, e : TypedExpr) {
		switch e.expr {
			case TBinop(OpAssign, e1, e2) | TBinop(OpAssignOp(_), e1, e2): switch(e1.expr) {
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
										typedAssignmentError(e);
									
								case _: 
									typedAssignmentError(e);
							}
							
						// Testing static field assignments
						case TTypeExpr(_):
							switch fa {
								case FStatic(_, cf):
									var field = cf.get().name;
									if (!mutableFieldNames.has(field)) typedAssignmentError(e);
								case _:
									typedAssignmentError(e);
							}
						case _:
							typedAssignmentError(e);
					}
					
				// Test for generic Map.set, for example StringMap
				// since it's abstract, the set method is replaced by an assignment.
				case TArray({expr: TField(e3, _), t:_, pos:_}, _):
					switch e3.t {
						case TInst(t, params): 
							// Allow haxe.ds.*Map
							var mapType = ~/^haxe\.ds\.[A-Z]\w+Map$/;
							
							if (!mapType.match(Std.string(t)))
								typedAssignmentError(e);
								
						case _:							
							typedAssignmentError(e);
					}
					
				case TLocal(v):
					if (safeLocals.exists(v.id)) return;
					
					// Very bizarre case, some Map.set are abstracted as
					// an assignment that must be picked apart.
					switch e2.expr {
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
					
					if (!v.name.startsWith("__mutable_")) {
						if (!Reflect.hasField(v, "meta")) return typedAssignmentError(e);

						// The compiler can generate assignments, trust them for now.
						#if (haxe_ver < 3.3)
						var meta : Array<Dynamic> = untyped v.meta;
						#else
						// Working properly in 3.3
						var meta = v.meta.get();
						#end
						if (!meta.exists(function(m) return m.name == ":compilerGenerated"))
							typedAssignmentError(e);
					}
					
				case _: 
					typedAssignmentError(e);
			}				
			case _: 
		}
		
		e.iter(preventAssignments.bind(inConstructor));
	}	
}
#end
