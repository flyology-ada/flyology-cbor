with Interfaces;

package Flyology_CBOR.Values
  with Pure
is
   subtype Argument is Interfaces.Unsigned_64;
   subtype Tag_Number is Interfaces.Unsigned_64;
   subtype Simple_Code is Interfaces.Unsigned_8;

   type Length_Kind is (Definite_Length, Indefinite_Length);

   type Item_Length is private;
   --  Length is eligible only for Definite_Length. Map lengths are pair counts; string lengths are
   --  encoded payload octet counts.

   function Definite (Value : Interfaces.Unsigned_64) return Item_Length;
   function Indefinite return Item_Length;
   function Kind (Item : Item_Length) return Length_Kind;

   function Length (Item : Item_Length) return Interfaces.Unsigned_64
   with Pre => Kind (Item) = Definite_Length;

   type Integer_Kind is (Unsigned_Integer, Negative_Integer);

   type Integer_Value is private;
   --  A negative value denotes the mathematical integer -1 - Argument without narrowing.

   function Unsigned (Argument : Interfaces.Unsigned_64) return Integer_Value;
   function Negative (Argument : Interfaces.Unsigned_64) return Integer_Value;
   function Kind (Item : Integer_Value) return Integer_Kind;
   function Integer_Argument (Item : Integer_Value) return Interfaces.Unsigned_64;

   type Float_Width is (Binary16, Binary32, Binary64);

   type Float_Value is private;
   --  Float_Value always has validated width/bits. Binary16 and Binary32 have no set high bits.

   type Float_Construction_Status is (Float_Constructed, Bits_Out_Of_Range);

   procedure Make_Float
     (Width  : Float_Width;
      Bits   : Interfaces.Unsigned_64;
      Item   : out Float_Value;
      Status : out Float_Construction_Status);

   function Width (Item : Float_Value) return Float_Width;
   function Bits (Item : Float_Value) return Interfaces.Unsigned_64;

   type Float_Category is
     (Finite, Positive_Infinity, Negative_Infinity, Not_A_Number);

   function Category (Item : Float_Value) return Float_Category;

private
   type Item_Length is record
      Length_Kind_Value : Length_Kind := Indefinite_Length;
      Length_Value      : Interfaces.Unsigned_64 := 0;
   end record;

   type Integer_Value is record
      Integer_Kind_Value : Integer_Kind := Unsigned_Integer;
      Argument_Value     : Interfaces.Unsigned_64 := 0;
   end record;

   type Float_Value is record
      Width_Value : Float_Width := Binary16;
      Bits_Value  : Interfaces.Unsigned_64 := 0;
   end record;
end Flyology_CBOR.Values;
