module ShardMath.Quaternion;
private import ShardMath.Matrix;
private import std.math;
import ShardMath.Vector;

/// Provides a quaternion, primarily used for 3D rotations. The imaginary components are excluded.
struct Quaternion  {

public:

	/// Initializes a new Quaternion with the given components.
	this(float X, float Y, float Z, float W) {
		this.X = X;
		this.Y = Y;
		this.Z = Z;
		this.W = W;
	}

	unittest {
		Quaternion Quat = Quaternion.Identity;
		assert(Quat.X == 0 && Quat.Y == 0 && Quat.Z == 0);
		assert(Quat.W == 1);
		Quat = Quaternion(1, 2, 3, 4);		
		assert(Quat.X == 1 && Quat.Y == 2 && Quat.Z == 3 && Quat.W == 4);
	}

	/// Initializes a new Quaternion with a Vector and Scalar.
	/// Params:
	/// 	Vector = The elements of this Quaternion in vector form.
	/// 	Scalar = The scalar value for the Quaternion.
	this(Vector3f Vector, float Scalar) {
		this(Vector.X, Vector.Y, Vector.Z, Scalar);
	}
	
	/// Calculates the magnitude of this Quaternion.
	@property float Magnitude() const {
		return sqrt(MagnitudeSquared);
	}	

	/// Calculates the magnitude of this Quaternion without square-rooting it.
	@property float MagnitudeSquared() const {
		return (X * X) + (Y * Y) + (Z * Z) + (W * W);
	}

	unittest {
		Quaternion Quat = Quaternion(1, 2, 3, 4);
		assert(Quat.Magnitude - 5.477 < 0.01f);
		assert(Quat.MagnitudeSquared - 30.0f < 0.01f);
	}

	/// Calculates whether this Quaternion is normalized.
	@property bool IsNormalized() const {
		return abs(MagnitudeSquared - 1) < 0.001f; // No need to sqrt, as we're comparing to see if it's 1.
	}

	unittest {
		assert(Quaternion.Identity.IsNormalized);
		assert(!Quaternion(1, 2, 3, 4).IsNormalized);
	}

	/// Creates an Identity Quaternion. When used for rotation, this indicates no rotation.
	@property static Quaternion Identity() {
		return Quaternion(0, 0, 0, 1);
	}

	/// Normalizes this Quaternion, altering this instance.
	void NormalizeInline() {		
		float Multiplier = 1f / MagnitudeSquared;
		//Vector *= Multiplier; // Alter the Vector to take advantage of Vector being optimized. Eventually.
		X *= Multiplier;
		Y *= Multiplier;
		Z *= Multiplier;
		W *= Multiplier;
	}

	unittest {
		Quaternion Quat = Quaternion(1, 2, 3, 4);
		Quat.NormalizeInline();
		assert(Quat.W - 0.73f < 0.01f && Quat.X - 0.18f < 0.01f && Quat.Y - 0.36f < 0.01f && Quat.Z - 0.54f < 0.01f);
	}

	/// Creates a new Quaternion from the given yaw, pitch, and roll.
	/// Params:
	/// 	Yaw = The angle, in radians, around the x-axis.
	/// 	Pitch = The angle, in radians, around the y-axis.
	/// 	Roll = The angle, in radians, around the z-axis.
	public static Quaternion FromYawPitchRoll(float Yaw, float Pitch, float Roll) {		
		Roll *= 0.5f;
		Pitch *= 0.5f;
		Yaw *= 0.5f;
		float RollY = sin(Roll), RollX = cos(Roll);
		float PitchY = sin(Pitch), PitchX = cos(Pitch);
		float YawY = sin(Yaw), YawX = cos(Yaw);
		Quaternion Result;
		Result.X = (YawX * PitchY * RollX) + (YawY * PitchX * RollY);
		Result.Y = (YawY * PitchX * RollX) - (YawX * PitchY * RollY);
		Result.Z = (YawX * PitchX * RollY) - (YawY * PitchY * RollX);
		Result.W = (YawX * PitchX * RollX) + (YawY * PitchY * RollY);
		return Result;
	}

	unittest {
		Quaternion Quat = Quaternion.FromYawPitchRoll(1, 2, 3);
		assert(Quat.W - 0.435 < 0.01f);
		assert(Quat.X - 0.310 < 0.01f);
		assert(Quat.Y + 0.718 < 0.01f);
		assert(Quat.Z - 0.444 < 0.01f);
	}

	/// Creates a Quaternion rotating Angle radians around the given axis.
	/// The axis must be a unit vector.
	/// Params:
	/// 	Axis = The axis to rotate around.
	/// 	Angle = The angle to rotate by.
	public static Quaternion FromAxisAngle(Vector3f Axis, float Angle) {
		assert(Axis.IsNormalized);
		float HalfAngle = Angle * 0.5f;
		float Y = sin(HalfAngle);
		float X = cos(HalfAngle);
		return Quaternion(Axis.X * Y, Axis.Y * Y, Axis.Z * Y, X);
	}

	unittest {
		Quaternion X = Quaternion.FromAxisAngle(Vector3f(1, 0, 0), PI_2);

	}

	public Quaternion opBinary(string Op)(in Quaternion Other) const if(Op == "+" || Op == "-" || Op == "/" || Op == "*") {
		static if(Op == "+" || Op == "-") {
			mixin("return Quaternion(this.X " ~ Op ~ " Other.X, this.Y " ~ Op ~ " Other.Y, this.Z " ~ Op ~ " Other.Z, this.W " ~ Op ~ " Other.W);");
		} else static if(Op == "*") {
			return Quaternion(
				(this.X * Other.W) + (this.W * Other.X) + (this.Y * Other.Z) - (Z * Other.Y),
				(this.Y * Other.W) + (this.W * Other.Y) + (this.Z * Other.X) - (this.X * Other.Z),
				(this.Z * Other.W) + (this.W * Other.Z) + (this.X * Other.Y) - (this.Y * Other.X),
				(this.W * Other.W) - (this.X * Other.X) - (this.Y * Other.Y) - (this.Z * Other.Z)
			);
		} else static if(Op == "/") {
			float MagSquared = Other.MagnitudeSquared;
			float InverseMag = 1f / MagSquared;
			float NX = -Other.X * InverseMag, NY = -Other.Y * InverseMag, NZ = -Other.Z * InverseMag;
			float NW = Other.W * InverseMag;
			return Quaternion(
				(this.X * NW) + (NX * this.W) + (this.Y * NZ) - (this.Z * NY),
				(this.Y * NW) + (NY * this.W) + (this.Z * NX) - (this.X * NZ),
				(this.Z * NW) + (NZ * this.W) + (this.X * NY) - (this.Y * NX),
				(this.W * NW) - ((this.X * NX) + (this.Y * NY) + (this.Z * NZ))
			);
		} else static assert(0, "Unsupported quaternions operator \'" ~ Op ~ "\'.");
	}

	bool opEquals(in Quaternion Other) const {
		return approxEqual(X, Other.X) && approxEqual(Y, Other.Y) && approxEqual(Z, Other.Z) && approxEqual(W, Other.W);
	}

	unittest {
		Quaternion quat = Quaternion(1, 2, 3, 4);
		quat = quat * quat;
		assert(quat.X == 8 && quat.Y == 16 && quat.Z == 24 && quat.W == 2);
		Quaternion Divided = quat / Quaternion(1, 2, 3, 4);
		assert(Divided == Quaternion(1, 2, 3, 4));
	}

	/// Returns a normalized value of this Quaternion.
	@property Quaternion Normalized() const {
		float Multiplier = 1f / MagnitudeSquared;
		return Quaternion(X * Multiplier, Y * Multiplier, Z * Multiplier, W * Multiplier);
	}

	/// Returns a rotation Matrix representing this Quaternion.
	Matrix4f ToMatrix() const {
		Matrix4f Result = void;
		float XX = this.X * this.X;
		float YY = this.Y * this.Y;
		float ZZ = this.Z * this.Z;
		float XY = this.X * this.Y;
		float ZW = this.Z * this.W;
		float ZX = this.Z * this.X;
		float YW = this.Y * this.W;
		float YZ = this.Y * this.Z;
		float XW = this.X * this.W;
		Result.M11 = 1f - (2f * (YY + ZZ));
		Result.M12 = 2f * (XY + ZW);
		Result.M13 = 2f * (ZX - YW);
		Result.M14 = 0f;
		Result.M21 = 2f * (XY - ZW);
		Result.M22 = 1f - (2f * (ZZ + XX));
		Result.M23 = 2f * (YZ + XW);
		Result.M24 = 0f;
		Result.M31 = 2f * (ZX + YW);
		Result.M32 = 2f * (YZ - XW);
		Result.M33 = 1f - (2f * (YY + XX));
		Result.M34 = 0f;
		Result.M41 = 0f;
		Result.M42 = 0f;
		Result.M43 = 0f;
		Result.M44 = 1f;
		return Result;
	}

	unittest {
		Quaternion quat = Quaternion(1, 2, 3, 4);
		Matrix4f AsMat = quat.ToMatrix();
		Matrix4f Expected = Matrix4f(-25, 28, -10, 0, -20, -19, 20, 0, 22, 4, -9, 0, 0, 0, 0, 1);
		assert(AsMat == Expected);
	}

	union {
		/// The elements of this Quaternion in array form.
		float[4] Elements;
		/// The elements of this Quaternion in vector form.
		Vector4f Vector;
		struct {
			/// The X, Y, Z, and W elements in this Quaternion.
			float X, Y, Z, W;
		}
	}
	
private:	
	
}