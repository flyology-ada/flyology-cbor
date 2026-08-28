package Flyology_CBOR.Profiles
  with Pure
is
   --  Callers construct every field explicitly; no default, factory, or profile constant exists.
   --  The initial implementation supports numeric version 1 for every declared family/policy.
   --  Other versions are unsupported and validation occurs before byte zero or destination begin.
   subtype Profile_Version is Positive;

   type Syntax_Family is (RFC_8949);
   type Unicode_Family is (Unicode_Scalars);
   type Acceptance_Family is (Well_Formed_CBOR);
   type Output_Policy is (Ordinary_Compact);
   --  Ordinary_Compact selects shortest unsigned arguments for integers, negative arguments,
   --  lengths, tags, and valid simple values. It preserves caller order and requested float width.
   --  It is neither canonical CBOR nor a whole-output preferred/deterministic encoding claim.

   type Versioned_Syntax is record
      Family  : Syntax_Family;
      Version : Profile_Version;
   end record;

   type Versioned_Unicode is record
      Family  : Unicode_Family;
      Version : Profile_Version;
   end record;

   type Versioned_Acceptance is record
      Family  : Acceptance_Family;
      Version : Profile_Version;
   end record;

   type Versioned_Output is record
      Policy  : Output_Policy;
      Version : Profile_Version;
   end record;

   type Parser_Profile is record
      Syntax     : Versioned_Syntax;
      Unicode    : Versioned_Unicode;
      Acceptance : Versioned_Acceptance;
   end record;

   type Writer_Profile is record
      Syntax     : Versioned_Syntax;
      Unicode    : Versioned_Unicode;
      Formatting : Versioned_Output;
   end record;

   type Profile_Status is
     (Profile_Supported, Profile_Unsupported, Profile_Incompatible);

   function Validate (Profile : Parser_Profile) return Profile_Status;
   function Validate (Profile : Writer_Profile) return Profile_Status;
end Flyology_CBOR.Profiles;
