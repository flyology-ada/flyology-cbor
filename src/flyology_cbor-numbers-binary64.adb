package body Flyology_CBOR.Numbers.Binary64 is

   use type Interfaces.Unsigned_64;

   function Promote_Finite
     (Bits          : Interfaces.Unsigned_64;
      Exponent_Bits : Natural;
      Fraction_Bits : Natural;
      Bias          : Natural) return Encoding
   is
      Sign      : constant Interfaces.Unsigned_64 :=
        Interfaces.Shift_Right (Bits, Exponent_Bits + Fraction_Bits);
      Exp_Mask  : constant Interfaces.Unsigned_64 := 2**Exponent_Bits - 1;
      Frac_Mask : constant Interfaces.Unsigned_64 := 2**Fraction_Bits - 1;
      Exponent  : Interfaces.Unsigned_64 :=
        Interfaces.Shift_Right (Bits, Fraction_Bits) and Exp_Mask;
      Fraction  : Interfaces.Unsigned_64 := Bits and Frac_Mask;
      Lead      : Natural;
      Unbiased  : Integer;
      Result    : Interfaces.Unsigned_64 := Interfaces.Shift_Left (Sign, 63);
   begin
      if Exponent = 0 and then Fraction = 0 then
         return Result;
      elsif Exponent /= 0 then
         Unbiased := Integer (Exponent) - Bias;
         Exponent := Interfaces.Unsigned_64 (Unbiased + 1023);
         Result := Result or Interfaces.Shift_Left (Exponent, 52);
         Result := Result or Interfaces.Shift_Left (Fraction, 52 - Fraction_Bits);
         return Result;
      end if;

      Lead := 0;
      for Bit in 0 .. Fraction_Bits - 1 loop
         if (Fraction and Interfaces.Shift_Left (1, Bit)) /= 0 then
            Lead := Bit;
         end if;
      end loop;
      Unbiased := Integer (Lead) + 1 - Bias - Fraction_Bits;
      Exponent := Interfaces.Unsigned_64 (Unbiased + 1023);
      Fraction := Fraction - Interfaces.Shift_Left (1, Lead);
      Result := Result or Interfaces.Shift_Left (Exponent, 52);
      Result := Result or Interfaces.Shift_Left (Fraction, 52 - Lead);
      return Result;
   end Promote_Finite;

   procedure Convert
     (Item   : Values.Float_Value;
      Result : out Conversion_Result)
   is
      Bits : constant Interfaces.Unsigned_64 := Values.Bits (Item);
   begin
      case Values.Category (Item) is
         when Values.Positive_Infinity =>
            Result := (Status_Value => Converted_Positive_Infinity, Result_Value => 0);
         when Values.Negative_Infinity =>
            Result := (Status_Value => Converted_Negative_Infinity, Result_Value => 0);
         when Values.Not_A_Number =>
            Result := (Status_Value => Converted_Not_A_Number, Result_Value => 0);
         when Values.Finite =>
            case Values.Width (Item) is
               when Values.Binary16 =>
                  Result :=
                    (Status_Value => Converted_Finite,
                     Result_Value => Promote_Finite (Bits, 5, 10, 15));
               when Values.Binary32 =>
                  Result :=
                    (Status_Value => Converted_Finite,
                     Result_Value => Promote_Finite (Bits, 8, 23, 127));
               when Values.Binary64 =>
                  Result := (Status_Value => Converted_Finite, Result_Value => Bits);
            end case;
      end case;
   end Convert;

   function Status (Result : Conversion_Result) return Conversion_Status is
     (Result.Status_Value);

   function Value (Result : Conversion_Result) return Encoding is
     (Result.Result_Value);

end Flyology_CBOR.Numbers.Binary64;
