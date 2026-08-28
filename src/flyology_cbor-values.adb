package body Flyology_CBOR.Values is

   use type Interfaces.Unsigned_64;

   function Definite (Value : Interfaces.Unsigned_64) return Item_Length is
     ((Length_Kind_Value => Definite_Length, Length_Value => Value));

   function Indefinite return Item_Length is
     ((Length_Kind_Value => Indefinite_Length, Length_Value => 0));

   function Kind (Item : Item_Length) return Length_Kind is
     (Item.Length_Kind_Value);

   function Length (Item : Item_Length) return Interfaces.Unsigned_64 is
     (Item.Length_Value);

   function Unsigned (Argument : Interfaces.Unsigned_64) return Integer_Value is
     ((Integer_Kind_Value => Unsigned_Integer, Argument_Value => Argument));

   function Negative (Argument : Interfaces.Unsigned_64) return Integer_Value is
     ((Integer_Kind_Value => Negative_Integer, Argument_Value => Argument));

   function Kind (Item : Integer_Value) return Integer_Kind is
     (Item.Integer_Kind_Value);

   function Integer_Argument (Item : Integer_Value) return Interfaces.Unsigned_64 is
     (Item.Argument_Value);

   procedure Make_Float
     (Width  : Float_Width;
      Bits   : Interfaces.Unsigned_64;
      Item   : out Float_Value;
      Status : out Float_Construction_Status)
   is
      In_Range : constant Boolean :=
        (case Width is
            when Binary16 => Bits <= 16#FFFF#,
            when Binary32 => Bits <= 16#FFFF_FFFF#,
            when Binary64 => True);
   begin
      if In_Range then
         Item := (Width_Value => Width, Bits_Value => Bits);
         Status := Float_Constructed;
      else
         Item := (Width_Value => Width, Bits_Value => 0);
         Status := Bits_Out_Of_Range;
      end if;
   end Make_Float;

   function Width (Item : Float_Value) return Float_Width is
     (Item.Width_Value);

   function Bits (Item : Float_Value) return Interfaces.Unsigned_64 is
     (Item.Bits_Value);

   function Category (Item : Float_Value) return Float_Category is
      Exponent : Interfaces.Unsigned_64;
      Fraction : Interfaces.Unsigned_64;
      Negative : Boolean;
   begin
      case Item.Width_Value is
         when Binary16 =>
            Exponent := Interfaces.Shift_Right (Item.Bits_Value, 10) and 16#1F#;
            Fraction := Item.Bits_Value and 16#03FF#;
            Negative := (Item.Bits_Value and 16#8000#) /= 0;
         when Binary32 =>
            Exponent := Interfaces.Shift_Right (Item.Bits_Value, 23) and 16#FF#;
            Fraction := Item.Bits_Value and 16#007F_FFFF#;
            Negative := (Item.Bits_Value and 16#8000_0000#) /= 0;
         when Binary64 =>
            Exponent := Interfaces.Shift_Right (Item.Bits_Value, 52) and 16#7FF#;
            Fraction := Item.Bits_Value and 16#000F_FFFF_FFFF_FFFF#;
            Negative := (Item.Bits_Value and 16#8000_0000_0000_0000#) /= 0;
      end case;

      if Exponent /=
        (case Item.Width_Value is
            when Binary16 => 16#1F#,
            when Binary32 => 16#FF#,
            when Binary64 => 16#7FF#)
      then
         return Finite;
      elsif Fraction /= 0 then
         return Not_A_Number;
      elsif Negative then
         return Negative_Infinity;
      else
         return Positive_Infinity;
      end if;
   end Category;

end Flyology_CBOR.Values;
