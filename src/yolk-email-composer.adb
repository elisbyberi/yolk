-------------------------------------------------------------------------------
--                                                                           --
--                   Copyright (C) 2010-, Thomas Løcke                   --
--                                                                           --
--  This library is free software;  you can redistribute it and/or modify    --
--  it under terms of the  GNU General Public License  as published by the   --
--  Free Software  Foundation;  either version 3,  or (at your  option) any  --
--  later version. This library is distributed in the hope that it will be   --
--  useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of  --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                     --
--                                                                           --
--  As a special exception under Section 7 of GPL version 3, you are         --
--  granted additional permissions described in the GCC Runtime Library      --
--  Exception, version 3.1, as published by the Free Software Foundation.    --
--                                                                           --
--  You should have received a copy of the GNU General Public License and    --
--  a copy of the GCC Runtime Library Exception along with this program;     --
--  see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
--  <http://www.gnu.org/licenses/>.                                          --
--                                                                           --
-------------------------------------------------------------------------------

with AWS.SMTP.Client;
with GNATCOLL.Email.Utils;

package body Yolk.Email.Composer is

   -------------------------
   --  Add_Custom_Header  --
   -------------------------

   procedure Add_Custom_Header
     (ES      : in out Structure;
      Name    : in     String;
      Value   : in     String;
      Charset : in     Character_Set := US_ASCII)
   is
      New_Header : Header_Data;
   begin
      New_Header.Charset := Charset;
      New_Header.Name := U (Name);
      New_Header.Value := U (Value);

      ES.Custom_Headers.Append (New_Header);
   end Add_Custom_Header;

   ---------------------------
   --  Add_File_Attachment  --
   ---------------------------

   procedure Add_File_Attachment
     (ES           : in out Structure;
      Path_To_File : in     String;
      Charset      : in     Character_Set := US_ASCII)
   is
      New_Attachment : Attachment_Data;
   begin
      New_Attachment.Charset        := Charset;
      New_Attachment.Path_To_File   := U (Path_To_File);
      ES.Attachment_List.Append (New_Attachment);

      ES.Has_Attachment := True;
   end Add_File_Attachment;

   ----------------
   --  Add_From  --
   ----------------

   procedure Add_From
     (ES      : in out Structure;
      Address : in     String;
      Name    : in     String := "";
      Charset : in     Character_Set := US_ASCII)
   is
      New_From : Email_Data;
   begin
      New_From.Address  := U (Address);
      New_From.Charset  := Charset;
      New_From.Name     := U (Name);
      ES.From_List.Append (New_Item => New_From);
   end Add_From;

   ---------------------
   --  Add_Recipient  --
   ---------------------

   procedure Add_Recipient
     (ES      : in out Structure;
      Address : in     String;
      Name    : in     String := "";
      Kind    : in     Recipient_Kind := To;
      Charset : in     Character_Set := US_ASCII)
   is
      New_Recipient : Email_Data;
   begin
      New_Recipient.Address   := U (Address);
      New_Recipient.Charset   := Charset;
      New_Recipient.Name      := U (Name);

      case Kind is
         when Bcc =>
            ES.Bcc_List.Append (New_Item => New_Recipient);
         when Cc =>
            ES.Cc_List.Append (New_Item => New_Recipient);
         when To =>
            ES.To_List.Append (New_Item => New_Recipient);
      end case;
   end Add_Recipient;

   --------------------
   --  Add_Reply_To  --
   --------------------

   procedure Add_Reply_To
     (ES      : in out Structure;
      Address : in     String;
      Name    : in     String := "";
      Charset : in     Character_Set := US_ASCII)
   is
      New_Reply_To : Email_Data;
   begin
      New_Reply_To.Address := U (Address);
      New_Reply_To.Charset := Charset;
      New_Reply_To.Name    := U (Name);
      ES.Reply_To_List.Append (New_Item => New_Reply_To);
   end Add_Reply_To;

   -----------------------
   --  Add_SMTP_Server  --
   -----------------------

   procedure Add_SMTP_Server
     (ES   : in out Structure;
      Host : in     String;
      Port : in     Positive := 25)
   is
      New_SMTP : SMTP_Server;
   begin
      New_SMTP.Host := U (Host);
      New_SMTP.Port := Port;
      ES.SMTP_List.Append (New_Item => New_SMTP);
   end Add_SMTP_Server;

   ---------------
   --  Is_Send  --
   ---------------

   function Is_Send
     (ES : in Structure)
      return Boolean
   is
   begin
      return ES.Email_Is_Sent;
   end Is_Send;

   ------------
   --  Send  --
   ------------

   procedure Send
     (ES : in out Structure)
   is
      US : Unbounded_String;
   begin
      Set_Type_Of_Email (ES => ES);

      case ES.Type_Of_Email is
         when Text =>
            Generate_Text_Email (ES);
         when Text_With_Attachment =>
            Generate_Text_With_Attachment_Email (ES);
         when Text_And_HTML =>
            Generate_Text_And_HTML_Email (ES);
         when Text_And_HTML_With_Attachment =>
            Generate_Text_And_HTML_With_Attachment_Email (ES);
      end case;

      if ES.SMTP_List.Is_Empty then
         raise No_SMTP_Host_Set;
      end if;

      GNATCOLL.Email.To_String (Msg    => ES.Composed_Message,
                                Result => US);

      Do_The_Actual_Sending :
      declare
         From              : AWS.SMTP.E_Mail_Data;
         To_Count          : Natural := Natural (ES.Bcc_List.Length) +
           Natural (ES.Cc_List.Length) + Natural (ES.To_List.Length);
         Recipients        : AWS.SMTP.Recipients (1 .. To_Count);
         Server            : AWS.SMTP.Receiver;
         Server_Failure    : Boolean := False;
         Status            : AWS.SMTP.Status;
      begin
         if ES.Sender.Address /= Null_Unbounded_String then
            From := AWS.SMTP.E_Mail (Name    => "",
                                     Address => To_String (ES.Sender.Address));
         else
            From := AWS.SMTP.E_Mail
              (Name    => "",
               Address => To_String (ES.From_List.First_Element.Address));
         end if;

         for i in ES.Bcc_List.First_Index .. ES.Bcc_List.Last_Index loop
            Recipients (To_Count) := AWS.SMTP.E_Mail
              (Name    => "",
               Address => To_String (ES.Bcc_List.Element (i).Address));

            To_Count := To_Count - 1;
         end loop;

         for i in ES.Cc_List.First_Index .. ES.Cc_List.Last_Index loop
            Recipients (To_Count) := AWS.SMTP.E_Mail
              (Name    => "",
               Address => To_String (ES.Cc_List.Element (i).Address));

            To_Count := To_Count - 1;
         end loop;

         for i in ES.To_List.First_Index .. ES.To_List.Last_Index loop
            Recipients (To_Count) := AWS.SMTP.E_Mail
              (Name    => "",
               Address => To_String (ES.To_List.Element (i).Address));

            To_Count := To_Count - 1;
         end loop;

         for i in ES.SMTP_List.First_Index .. ES.SMTP_List.Last_Index loop
            Server := AWS.SMTP.Client.Initialize
              (Server_Name => To_String (ES.SMTP_List.Element (i).Host),
               Port        => ES.SMTP_List.Element (i).Port);

            declare
            begin
               AWS.SMTP.Client.Send (Server => Server,
                                     From   => From,
                                     To     => Recipients,
                                     Source => To_String (US),
                                     Status => Status);

            exception
               when others =>
                  Server_Failure := True;
            end;

            if Server_Failure then
               --  Reset Server_Failure
               Server_Failure := False;
            else
               if AWS.SMTP.Is_Ok (Status => Status) then
                  ES.Email_Is_Sent := True;
                  exit;
               end if;
            end if;
         end loop;
      end Do_The_Actual_Sending;
   end Send;

   ------------
   --  Send  --
   ------------

   procedure Send
     (ES           : in out Structure;
      From_Address : in     String;
      From_Name    : in     String := "";
      To_Address   : in     String;
      To_Name      : in     String := "";
      Subject      : in     String;
      Text_Part    : in     String;
      SMTP_Server  : in     String := "localhost";
      SMTP_Port    : in     Positive := 25;
      Charset      : in     Character_Set := US_ASCII)
   is
   begin
      Add_From (ES      => ES,
                Address => From_Address,
                Name    => From_Name,
                Charset => Charset);

      Add_Recipient (ES      => ES,
                     Address => To_Address,
                     Name    => To_Name,
                     Kind    => To,
                     Charset => Charset);

      Set_Subject (ES      => ES,
                   Subject => Subject,
                   Charset => Charset);

      Set_Text_Part (ES      => ES,
                     Part    => Text_Part,
                     Charset => Charset);

      Add_SMTP_Server (ES   => ES,
                       Host => SMTP_Server,
                       Port => SMTP_Port);

      Send (ES => ES);
   end Send;

   ------------
   --  Send  --
   ------------

   procedure Send
     (ES           : in out Structure;
      From_Address : in     String;
      From_Name    : in     String := "";
      To_Address   : in     String;
      To_Name      : in     String := "";
      Subject      : in     String;
      Text_Part    : in     String;
      HTML_Part    : in     String;
      SMTP_Server  : in     String := "localhost";
      SMTP_Port    : in     Positive := 25;
      Charset      : in     Character_Set := US_ASCII)
   is
   begin
      Set_HTML_Part (ES      => ES,
                     Part    => HTML_Part,
                     Charset => Charset);

      Send (ES           => ES,
            From_Address => From_Address,
            From_Name    => From_Name,
            To_Address   => To_Address,
            To_Name      => To_Name,
            Subject      => Subject,
            Text_Part    => Text_Part,
            SMTP_Server  => SMTP_Server,
            SMTP_Port    => SMTP_Port,
            Charset      => Charset);
   end Send;

   ---------------------
   --  Set_HTML_Part  --
   ---------------------

   procedure Set_HTML_Part
     (ES      : in out Structure;
      Part    : in     String;
      Charset : in     Character_Set := US_ASCII)
   is
      use GNATCOLL.Email.Utils;

      US : Unbounded_String;
   begin
      Encode (Str     => Part,
              Charset => Get_Charset (Charset => Charset),
              Result  => US);

      ES.HTML_Part.Content := US;
      ES.HTML_Part.Charset := Charset;

      ES.Has_HTML_Part := True;
   end Set_HTML_Part;

   ------------------
   --  Set_Sender  --
   ------------------

   procedure Set_Sender
     (ES      : in out Structure;
      Address : in     String;
      Name    : in     String := "";
      Charset : in     Character_Set := US_ASCII)
   is
   begin
      ES.Sender.Address := U (Address);
      ES.Sender.Charset := Charset;
      ES.Sender.Name    := U (Name);
   end Set_Sender;

   -------------------
   --  Set_Subject  --
   -------------------

   procedure Set_Subject
     (ES      : in out Structure;
      Subject : in     String;
      Charset : in     Character_Set := US_ASCII)
   is
   begin
      ES.Subject.Content := U (Subject);
      ES.Subject.Charset := Charset;
   end Set_Subject;

   ---------------------
   --  Set_Text_Part  --
   ---------------------

   procedure Set_Text_Part
     (ES      : in out Structure;
      Part    : in     String;
      Charset : in     Character_Set := US_ASCII)
   is
      use GNATCOLL.Email.Utils;

      US : Unbounded_String;
   begin
      Encode (Str     => Part,
              Charset => Get_Charset (Charset => Charset),
              Result  => US);

      ES.Text_Part.Content := US;
      ES.Text_Part.Charset := Charset;

      ES.Has_Text_Part := True;
   end Set_Text_Part;

end Yolk.Email.Composer;
