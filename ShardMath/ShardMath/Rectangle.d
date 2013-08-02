module ShardMath.Rectangle;

import ShardMath.Vector;
import std.traits;

/// Values indicating how a specified object is contained in a different object.
enum ContainmentType {
	/// The object fully contains the other object.
	Contains,
	/// The object overlaps with the other object, but does not fully contain it.
	Intersects,
	/// The two objects do not meet.
	Disjoints
}

/// Represents a rectangle containing an X coordinate, Y coordinate, Width, and Height.
struct Rectangle(T) {	
	alias Vector!(2, T) Point;
	
	/// Instantiates a new instance of the Rectangle structure.
	/// Params:
	///		X = The X coordinate for this Rectangle.
	///		Y = The Y coordinate for this Rectangle.
	///		Width = The width of this Rectangle.
	///		Height = The height of this Rectangle.
	this(T X, T Y, T Width, T Height) {
		this.X = X; 
		this.Y = Y;
		this.Width = Width; 
		this.Height = Height;
	}
	
	/// Returns the smallest Rectangle capable of containing the specified amount of points.
	/// Params: Points = The array of points to create a Rectangle from.
	static Rectangle!(T) FromPoints(const Point[] Points) {
		if(Points.length == 0)
			return Rectangle();
		T minX = T.max, minY = T.max; 
		T maxX = T.min, maxY = T.min;		
		foreach(ref point; Points) {
			minX = point.X < minX ? point.X : minX;
			minY = point.Y < minY ? point.Y : minY;
			maxX = point.X > maxX ? point.X : maxX;
			maxY = point.Y > maxY ? point.Y : maxY;
		}		
		return Rectangle(minX, minY, maxX - minX, maxY - minY);
	}	

	/// Returns an empty rectangle.
	@property static Rectangle!(T) Empty() {
		return Rectangle!(T)(0, 0, 0, 0);
	}
	
	/// Determines how this Rectangle contains the specified Rectangle.
	/// BUG: This method is not fully implemented yet.
	@disable
	ContainmentType Contains(const ref Rectangle!(T) other) const {
		if(X >= other.X || Y >= other.Y)
			return ContainmentType.Disjoints;
		if(Right >= other.Right && Bottom >= other.Bottom)
			return ContainmentType.Contains;
		return ContainmentType.Intersects;		
	}	
	
	/// Determines whether this Rectangle contains the specified point.
	bool Contains(in Point point) const {
		return X <= point.X && point.X <= (X + Width) && Y <= point.Y && point.Y <= (Y + Height);
	}
	
	/// Returns a Point containing the position of this Rectangle.
	@property Point Position() const {
		return Point(X, Y);
	}	
	
	/// Returns a Point containing the size of this Rectangle.
	@property Point Size() const {
		return Point(Width, Height);
	}
	
	/// Returns the right-most coordinate in this rectangle.
	@property T Right() const {
		return X + Width;
	}
	
	/// Returns the bottom-most coordinate in this Rectangle.
	@property T Bottom() const {
		return Y + Height;		
	}

	const Type opCast(Type)() if(hasMember!(Type, "X") && hasMember!(Type, "Y") && hasMember!(Type, "Width") && hasMember!(Type, "Height")) {	
		Type result;
		result.X = cast(typeof(result.X))X;
		result.Y = cast(typeof(result.Y))Y;
		result.Width = cast(typeof(result.Width))Width;
		result.Height = cast(typeof(result.Height))Height;
		return result;
	}
	
	union {
		struct {
			/// The top-left coordinate for this rectangle.
			T X;
			/// The top-right coordinate for this rectangle.
			T Y;
			/// The width of this rectangle.
			T Width;
			/// The height of this rectangle.
			T Height;
		}
		/// Provides array access to the elements of this rectangle.
		T[4] Elements;
	}
}

alias Rectangle!(int) Rectanglei;
alias Rectangle!(float) Rectanglef; 