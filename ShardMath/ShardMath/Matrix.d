module ShardMath.Matrix;
private import std.path;
private import std.traits;
import std.conv;
import ShardMath.Vector;
import std.exception;
import std.math;
import std.c.string;

/// Represents a row-major square NxN coefficient matrix with helper methods for graphics programming.
struct Matrix(int N, T) if(N >= 2) {

public:		

	/// If T is a floating point type, this is alased to T; otherwise, float.
	/// This is used for operations that do not have a meaningful result for integer vectors.
	alias Select!(isFloatingPoint!(T), T, float) DecimalType;	

	// For external access, outside this class. Probably a better way?
	alias N NumRows;
	alias N NumColumns;
	alias T ElementType;

	private static string ConstructorMixin() {
		string Result = "public this(";		
		for(int y = 1; y <= N; y++) {
			for(int x = 1; x <= N; x++) {
				Result ~= "T M" ~ to!string(y) ~ to!string(x) ~ ", ";
			}
		}
		Result = Result[0..$-2];
		Result ~= ") {\r\n";	
		for(int y = 1; y <= N; y++) {
			for(int x = 1; x <= N; x++) {
				string Element = "M" ~ to!string(y) ~ to!string(x);
				Result ~= "this." ~ Element ~ " = " ~ Element ~ ";\r\n";
			}
		}	
		Result ~= "}\r\nthis(T[N][N] Elements) { this.Elements = Elements; }\r\nthis(T Value) { for(int i = 0; i < N; i++) this.ElementsSingleDim[i] = Value; }";		
		return Result;
	}

	/// Creates a new matrix with the given elements.
	mixin(ConstructorMixin());	

	unittest {
		Matrix2f Test1 = Matrix2f(1, 2, 3, 4);
		assert(Test1.M11 == 1);
		assert(Test1.M12 == 2);
		assert(Test1.M21 == 3);
		assert(Test1.M22 == 4);

	}

	/// Gets an instance of the Identity matrix.
	@property static Matrix!(N, T) Identity() {
		return _Identity;
	}

	// TODO: Try to implement pass-by-ref.

	Matrix opBinary(string op)(in Matrix Second) if(op == "+" || op == "-" || op == "*" || op == "/") {
		Matrix Result;
		mixin(GenOp(op, "Result", "this", "Second"));		
		return Result;		
	}

	ref Matrix opOpAssign(string op)(in Matrix Other) if(op == "+" || op == "-" || op == "*" || op == "/") {		
		Matrix Result = this.opBinary!op(Other);
		this = Result;
		return this;
		// TODO: Bring this back!
		//mixin(GenOpAssign(op, "this", "Other"));
		//return this;
	}

	T opIndex(size_t Row, size_t Column) const {
		return this.ElementsSingleDim[Row * N + Column];
	}

	void opIndexAssign(size_t Row, size_t Column, T Value) {
		this.ElementsSingleDim[Row * N + Column] = Value;
	}

	int opApply(int delegate(ref T) dg) {
		int Result;
		foreach(ref T Element; this.ElementsSingleDim)
			if((Result = dg(Element)) != 0)
				break;
		return Result;
	}

	bool opEquals(in Matrix Other) const {
		for(size_t i = 0; i < ElementsSingleDim.length; i++)
			if(!approxEqual(ElementsSingleDim[i], Other.ElementsSingleDim[i]))
				return false;
		return true;
	}

	ref Matrix opAssign(in Matrix Other) {		
		//mixin(GenOpAssign("", "this", "Other"));
		//return this;
		memcpy(this.ElementsSingleDim.ptr, Other.ElementsSingleDim.ptr, T.sizeof * N * N);		
		return this;
	}

	static if(N == 4) {		
		/// Creates a scalar matrix with the given scale.
		static Matrix CreateScale(T Scale) {
			Matrix Result;
			Result.M11 = Scale;
			Result.M22 = Scale;
			Result.M33 = Scale;		
			Result.M44 = 1;
			return Result;	
		}

		/// Ditto
		static Matrix CreateScale(Vector!(3, T) Scale...) {
			Matrix Result;
			Result.M11 = Scale.X;
			Result.M22 = Scale.Y;
			Result.M33 = Scale.Z;
			Result.M44 = 1;
			return Result;
		}

		/// Creates a Matrix with the given translation value.
		static Matrix CreateTranslation(Vector!(3, T) Translation) {
			Matrix Result = Matrix.Identity;
			Result.Translation = Translation;
			return Result;
		}

		/// Ditto
		static Matrix CreateTranslation(T X, T Y, T Z) {
			return CreateTranslation(Vector!(3, T)(X, Y, Z));
		}
		
		/// Gets or sets the position component of this matrix.		
		@property Vector!(3, T) Translation() const {
			return Vector!(3, T)(M41, M42, M43);
		}

		/// Ditto
		@property void Translation(Vector!(3, T) Value) {	
			M41 = Value.X;
			M42 = Value.Y;
			M43 = Value.Z;		
		}

		/// Gets the direction that indicates Right, after the rotations applied by this Matrix.
		@property Vector!(3, T) Right() const {
			return *(cast(Vector!(3, T)*)&M11);		
		}
		
		/// Gets the direction that indicates Left, after the rotations applied by this Matrix.
		@property Vector!(3, T) Left() const {
			return -Right;
		}

		/// Gets the direction that indicates Forward, after the rotations applied by this Matrix.
		@property Vector!(3, T) Forward() const {
			return -Backward;
		}

		/// Gets the direction that indicates Forward, after the rotations applied by this Matrix.
		@property Vector!(3, T) Backward() const {
			return *(cast(Vector!(3, T)*)&M31);
		}
	}

	static if(N == 4 && isFloatingPoint!(T)) {
		/// Creates a Matrix to apply a rotation around the X-axis.
		/// Params:
		/// 	Radians = The amount of radians to rotate around the X axis.
		static Matrix CreateRotationX(T Radians) {
			Matrix Result = Matrix.Identity;
			T X = cast(T)cos(Radians);
			T Y = cast(T)sin(Radians);
			Result.M22 = X;
			Result.M23 = Y;
			Result.M32 = -Y;
			Result.M33 = X;
			return Result;
		}

		/// Creates a Matrix to apply a rotation around the Y-axis.
		/// Params:
		/// 	Radians = The amount of radians to rotate around the Y axis.
		static Matrix CreateRotationY(T Radians) {
			Matrix Result = Matrix.Identity;
			T X = cast(T)cos(Radians);
			T Y = cast(T)sin(Radians);
			Result.M11 = X;
			Result.M13 = -Y;
			Result.M31 = Y;
			Result.M33 = X;
			return Result;
		}

		/// Creates a Matrix to apply a rotation around the Z-axis.
		/// Params:
		/// 	Radians = The amount of radians to rotate around the Z axis.
		static Matrix CreateRotationZ(T Radians) {
			Matrix Result = Matrix.Identity;
			T X = cast(T)cos(Radians);
			T Y = cast(T)sin(Radians);
			Result.M11 = X;
			Result.M12 = Y;
			Result.M21 = -Y;
			Result.M22 = X;
			return Result;
		}		
	}

	/// Returns a transposed version of this matrix.
	@property Matrix!(N, T) Transposed() const {
		Matrix Result = void;		
		mixin(TransposeMixin());
		return Result;
	}

	private static string TransposeMixin() {
		string MixinString = "";
		for(int y = 1; y <= N; y++) {
			for(int x = 1; x <= N; x++) {				
				MixinString ~= ("Result.M" ~ to!string(y) ~ to!string(x) ~ " = this.M" ~ to!string(x) ~ to!string(y) ~ ";");
			}
		}	
		return MixinString;	
	}

	/+
	/// Calculates the Minor of this Matrix for the given row and column.
	/// That is, this Matrix with the given Row and Column removed.
	/// Params:
	/// 	Row = The row to calculate the cofactor for.
	/// 	Column = The column to calculate the cofactor for.
	T Minor(int Row, int Column) {
		assert(Row <= NumRows && Column <= NumColumns && Row > 0 && Column > 0);
		alias Matrix!(N - 1, T) RetType;
		RetType Result = void;
		for(int y = 1; y <= N; y++) {
			for(int x = 1; x <= N; x++) {
				
			}
		}
		mixin(MinorMixin(Row, Column));
		return Result.Determinant;		
	}

	private static string MinorMixin(int Row, int Column) {
		static assert(0, "Change to using Elements instead of mixing in stuff we don't even know at compile-time.");
		// Remember, Minor = det(Matrix without Row, Column), Cofactor = -1^(Row+Column) * Minor(Row, Column).
		string Result = "int TargetRow = 0, TargetCol = 0; ";
		for(int Y = 1; Y < N; Y++) {
			for(int X = 1; X < N; X++) {
				Result ~= "TargetRow = Y >= Row ? Y - 1 : Y; ";
				Result ~= "TargetCol = X >= Column ? X - 1 : X; ";
				Result ~= "Result.M" ~ to!string(TargetRow) ~ to!string(TargetCol) ~ " = this.M" ~ to!string(Y) ~ to!string(X) ~ "; ";
			}
		}
		return Result;
	}	

	/// Calculates the Cofactor of this Matrix for the given row and column.
	/// Params:
	/// 	Row = The row to calculate the cofactor for.
	/// 	Column = The column to calculate the cofactor for.
	T Cofactor(int Row, int Column) {
		return (Row + Column) % 2 == 0 ? Minor(Row, Column) : -Minor(Row, Column);
	}

	unittest {
		Matrix4f TestMat = Matrix4f(
			 4,  0, 10,  4,
			-1,  2,  3,  9,
			 5, -5, -1,  6,
			 3,	 7,  1, -2
		);
		Matrix3f Actual = TestMat.Minor(3, 3);
		Matrix3f Expected = Matrix3f(
			 4,  0,  4,
			-1,  2,  9,
			 3,  7, -2
		);
		assert(Actual == Expected);
		assert(TestMat.Cofactor(3, 3) == Actual);
	}+/
	
	/// Calculates the Determinant of this matrix.
	@property T Determinant() {		
		static if(N == 2) {
			return (M11 * M22) - (M12 * M21);			
		} else static if(N == 3) {
			return (M11 * M22 * M33) + (M12 * M23 * M31) + (M13 * M21 * M32) - (M12 * M21 * M33) - (M11 * M23 * M32) - (M13 * M22 * M31);
		} else static if(N == 4) {
			assert(0, "Not yet implemented.");
			// Calculate with method of cofactors.
		} else {
			assert(0, "Not yet implemented.");
		}		
	}

	unittest {
		assert(Matrix2f
			(-5, 1, 
			  1, 3
		).Determinant == -16);
		float Det = Matrix2f(
			4, -1, 
			2, -1/2f
		).Determinant;
		assert(abs(Det) < 0.0001f);
	}

	static if(isFloatingPoint!(T)) {
		// TODO: Support DecimalType. Keep in mind that InvertInline wouldn't work.

		version(None) { // TODO: Broked.
		/// Calculates the inverse of this Matrix.
		@property Matrix!(N, T) Inverse() const {
			// TODO: Consider optimizing.
			Matrix!(N, T) Result = this;			
			Result.InvertInline();
			return Result;			
		}

		unittest {
			Matrix2f Inverted = Matrix2f(-5, 1, 1, 3).InvertInline();
			assert(Inverted == Matrix2f(-3/16f, 1/16f, 1/16f, 5/16f));
		}

		/// Inverts this Matrix by altering it's own elements, returning the same instance of the Matrix.
		ref Matrix InvertInline() {
			assert(IsInvertible);
			// TODO: Can optimize this by storing the results of the calculations we used for Determinant.
			static if(N == 2) {				
				T Det = Determinant;
				assert(Det != 0);
				T InvDet = 1f / Det;			
				M22 *= InvDet;
				M12 *= -InvDet;
				M21 *= -InvDet;
				M11 *= InvDet;
				return this;
			}
			assert(0, "Not yet implemented.");
		}
		}
	}

	/// Indiciates whether this Matrix can be inverted.
	@property bool IsInvertible() {
		return abs(Determinant) > 0.0001f;
	}	

	static if(N == 4 && isFloatingPoint!(T)) {
		/// Creates a perspective field of view matrix with the given parameters.
		/// This Matrix is valid as both a DirectX and OpenGL Projection Matrix, but for OpenGL must be transposed.
		/// Note that glUniformMatrix4fv contains a transpose parameter.
		/// Also note that using a transposed version of this for OpenGL results in different GLSL multiplication order (Model * View * Projection).
		/// Params:
		/// 	FOV = The field of view, in radians.
		/// 	AspectRatio = The aspect ratio for the viewport this matrix is being used on.
		/// 	NearPlane = The closest that anything will be rendered.
		/// 	ViewDistance = The maximum distance to view, such that FarPlane is equal to NearPlane + ViewDistance.		
		static Matrix!(N, T) FieldOfView(float FOV, float AspectRatio, float NearPlane, float ViewDistance) {
			T FarPlane = NearPlane + ViewDistance;
			enforce(FarPlane > NearPlane && NearPlane > 0 && FOV > 0);								
			Matrix!(N, T) Result = void;
			T CalcFOV = cast(T)(1f / tan(FOV * 0.5f));
			T FovAR = CalcFOV / AspectRatio;
			Result.M11 = FovAR;
			Result.M12 = Result.M13 = Result.M14 = 0;
			Result.M22 = CalcFOV;
			Result.M21 = Result.M23 = Result.M24 = 0;
			Result.M31 = Result.M32 = 0;
			Result.M33 = FarPlane / (NearPlane - FarPlane);
			Result.M34 = -1;
			Result.M41 = Result.M42 = Result.M44 = 0;
			Result.M43 = (NearPlane * FarPlane) / (NearPlane - FarPlane);
			return Result;		
		}
	
		/// Creates a matrix used to look at the given target from the given position.
		/// This Matrix is valid as both a DirectX and OpenGL View Matrix, but for OpenGL must be transposed.
		/// Note that glUniformMatrix4fv contains a transpose parameter.
		/// Params:
		/// 	Position = The position of the eye, in world space.
		/// 	Target = The position of the target, in world space.
		/// 	Up = A vector representing the up direction from the position.
		static Matrix!(N, T) LookAt(Vector!(3, T) Position, Vector!(3, T) Target, Vector!(3, T) Up) {		
			Vector!(3, T) First = (Position - Target);
			First.NormalizeInline();
			Vector!(3, T) Second = Vector!(3, T).Cross(Up, First);
			Second.NormalizeInline();
			Vector!(3, T) Third = Vector!(3, T).Cross(First, Second);

			Matrix!(N, T) Result = Matrix!(N, T).Identity;		
			Result.M11 = Second.X;
			Result.M12 = Third.X;
			Result.M13 = First.X;
			Result.M21 = Second.Y;
			Result.M22 = Third.Y;
			Result.M23 = First.Y;
			Result.M31 = Second.Z;
			Result.M32 = Third.Z;
			Result.M33 = First.Z;

			Result.M41 = -Vector!(3, T).Dot(Second, Position);
			Result.M42 = -Vector!(3, T).Dot(Third, Position);
			Result.M43 = -Vector!(3, T).Dot(First, Position);
			Result.M44 = 1;			
			return Result;
		}
	}

	/// Gets a string representation of this Matrix.
	string toString() const {
		// TODO: Consider optimizing; sometimes it may be useful to write a large number of matrices to a log? Of course, it should be binary format then...
		string Result = "";
		for(int y = 1; y <= N; y++) {
			Result ~= '[';
			for(int x = 1; x <= N; x++) {
				Result ~= to!string(ElementsSingleDim[(y - 1) * N + (x - 1)]);
				if(x != N)
					Result ~= ", ";
			}
			Result ~= ']';
			if(y != N)
				Result ~= "\n";
		}
		return Result;
	}

	unittest {
			
		Matrix2f Test = Matrix2f(1, 2, 3, 4);
		string Expected = "[1, 2]" ~ "\n" ~ "[3, 4]";
		assert(to!string(Test) == Expected);
	}
	 
	private static string ElementMixin() {
		string Result = "union { T[N * N] ElementsSingleDim; T[N][N] Elements;\r\nstruct {";
		for(int y = 1; y <= N; y++) {
			Result ~= "union {\r\n Vector!(N, T) Row" ~ to!string(y) ~ ";\r\nstruct {";
			for(int x = 1; x <= N; x++) {
				string Element = "M" ~ to!string(y) ~ to!string(x);
				Result ~= "T " ~ Element ~ ";\r\n";
			}
			Result ~= "}\r\n}";
		}
		Result ~= "}\r\n}";
		return Result;
	}

	mixin(ElementMixin());	

private:
	static __gshared Matrix!(N, T) _Identity;	
	
	shared static this() {		
		for(size_t Row = 0; Row < N; Row++) {
			for(size_t Col = 0; Col < N; Col++) {
				if(Row == Col)
					_Identity.Elements[Row][Col] = 1;
				else
					_Identity.Elements[Row][Col] = 0;
			}
		}
		for(size_t i = 0; i < N; i++) {
			_Identity.Elements[i][i] = 1;
		}
	}	

	static string GenOp(string Operator, string AppliedTo, string Left, string Right) {
		// TODO: SIMD		
		//static assert(Operator.length == 1, "Expected single operator, such as + or -.");
		string Result = "";		
		for(int x = 1; x <= N; x++) {
			for(int y = 1; y <= N; y++) {
				string Element = "M" ~ to!string(y) ~ to!string(x);
				if(Operator != "*")
					Result ~= AppliedTo ~ "." ~ Element ~ " = " ~ Left ~ "." ~ Element ~ " " ~ Operator ~ " " ~ Right ~ "." ~ Element ~ "; ";
				else {
					Result ~= AppliedTo ~ "." ~ Element ~ " = 0; ";
					for(int z = 1; z <= N; z++) {
						string LeftElement = "M" ~ to!string(x) ~ to!string(z);
						string RightElement = "M" ~ to!string(z) ~ to!string(y);
						Result ~= AppliedTo ~ "." ~ Element ~ "+= " ~ Left ~ "." ~ LeftElement ~ " * " ~ Right ~ "." ~ RightElement ~ "; ";
					}
				}					
			}
		}		
		return Result;
	}	

	static string GenOpAssign(string Operator, string Left, string Right) {
		string LeftAccess = Left == "this" ? "" : Left ~ ".";
		// TODO: SIMD		
		//static assert(Operator.length == 1, "Expected single operator, such as + or -.");
		string Result = "";		
		// TODO: Less hackish resulting in actual performance benefits for inlining, not costs...
		if(Operator == "*") {			
			enum string tmpMatrixName = "__tmp_MatrixNT_opAssign";
			if(LeftAccess != "")
				Result ~= "Matrix " ~ tmpMatrixName ~ " = *" ~ LeftAccess ~ " * " ~ Right ~ "; ";
			else
				Result ~= "Matrix " ~ tmpMatrixName ~ " = Matrix.opBinary!(\"*\")(" ~ Right ~ "); ";
		} else {
			for(int x = 1; x <= N; x++) {
				for(int y = 1; y <= N; y++) {								
					string Element = "M" ~ to!string(x) ~ to!string(y);					
					if(Operator != "*")
						Result ~= LeftAccess ~ Element ~ " " ~ Operator ~ "= " ~ Right ~ "." ~ Element ~ "; ";
					else
						Result ~= LeftAccess ~ Element ~ " = " ~ Right ~ "." ~ Element ~ "; ";
				}
			}		
		}				
		return Result;
	}		
	
	/// Calculates the Trace of this Matrix, usually noted by tr(Matrix).
	@property T Trace() {
		T Sum = 0;
		mixin(TraceMixin());
		return Sum;
	}
	
	private static string TraceMixin() {
		string Result = "";
		for(int i = 1; i <= N; i++) {
			Result ~= "Sum += this.M" ~ to!string(i) ~ to!string(i) ~ ";";
		}
		return Result;
	}	
}


alias Matrix!(2, float) Matrix2f;
alias Matrix!(2, double) Matrix2d;
alias Matrix!(2, int) Matrix2i;
alias Matrix!(3, float) Matrix3f;
alias Matrix!(3, double) Matrix3d;
alias Matrix!(3, int) Matrix3i;
alias Matrix!(4, float) Matrix4f;
alias Matrix!(4, double) Matrix4d;
alias Matrix!(4, int) Matrix4i;