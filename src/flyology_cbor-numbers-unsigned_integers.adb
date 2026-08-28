with Interfaces;

package body Flyology_CBOR.Numbers.Unsigned_Integers is

   use type Values.Integer_Kind;

   procedure Convert
     (Item   : Values.Integer_Value;
      Result : out Conversion_Result)
   is
      use type Interfaces.Unsigned_64;

      Argument : constant Interfaces.Unsigned_64 := Values.Integer_Argument (Item);
   begin
      if Values.Kind (Item) = Values.Negative_Integer then
         Result := (Status_Value => Negative_Value, Result_Value => Value_Type'First);
      elsif Value_Type'Modulus > 2**64
        or else Argument <= Interfaces.Unsigned_64 (Value_Type'Modulus - 1)
      then
         Result := (Status_Value => Converted, Result_Value => Value_Type (Argument));
      else
         Result := (Status_Value => Above_Range, Result_Value => Value_Type'First);
      end if;
   end Convert;

   function Status (Result : Conversion_Result) return Conversion_Status is
     (Result.Status_Value);

   function Value (Result : Conversion_Result) return Value_Type is
     (Result.Result_Value);

end Flyology_CBOR.Numbers.Unsigned_Integers;
