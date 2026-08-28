with Interfaces;

package body Flyology_CBOR.Numbers.Signed_Integers is

   use type Interfaces.Integer_128;
   use type Values.Integer_Kind;

   procedure Convert
     (Item   : Values.Integer_Value;
      Result : out Conversion_Result)
   is
      Argument : constant Interfaces.Unsigned_64 := Values.Integer_Argument (Item);
      Wide     : Interfaces.Integer_128;
   begin
      if Values.Kind (Item) = Values.Unsigned_Integer then
         Wide := Interfaces.Integer_128 (Argument);
         if Wide > Interfaces.Integer_128 (Value_Type'Last) then
            Result := (Status_Value => Above_Range, Result_Value => Value_Type'First);
         elsif Wide < Interfaces.Integer_128 (Value_Type'First) then
            Result := (Status_Value => Below_Range, Result_Value => Value_Type'First);
         else
            Result :=
              (Status_Value => Converted,
               Result_Value => Value_Type (Wide));
         end if;
      else
         Wide := -1 - Interfaces.Integer_128 (Argument);
         if Wide < Interfaces.Integer_128 (Value_Type'First) then
            Result := (Status_Value => Below_Range, Result_Value => Value_Type'First);
         elsif Wide > Interfaces.Integer_128 (Value_Type'Last) then
            Result := (Status_Value => Above_Range, Result_Value => Value_Type'First);
         else
            Result := (Status_Value => Converted, Result_Value => Value_Type (Wide));
         end if;
      end if;
   end Convert;

   function Status (Result : Conversion_Result) return Conversion_Status is
     (Result.Status_Value);

   function Value (Result : Conversion_Result) return Value_Type is
     (Result.Result_Value);

end Flyology_CBOR.Numbers.Signed_Integers;
