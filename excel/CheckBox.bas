Attribute VB_Name = "Module1"
Sub CreateCheckBoxes()
'Declare variables
Dim c As Range
Dim chkBox As CheckBox
Dim chkBoxRange As Range
Dim cellLinkOffsetCol As Double
'Ingore errors if user clicks Cancel or X
On Error Resume Next
'Input Box to select cell Range
Set chkBoxRange = Application.InputBox(Prompt:="Select cell range", Title:="Create checkboxes", Type:=8)
'Exit the code if user clicks Cancel or X
If Err.Number <> 0 Then Exit Sub
'Turn error checking back on
On Error GoTo 0
'Loop through each cell in the selected cells
For Each c In chkBoxRange 'Add the checkbox
 Set chkBox = chkBoxRange.Parent.CheckBoxes.Add(0, 1, 1, 0)
 With chkBox
 'Set the checkbox position
 .Top = c.Top + c.Height / 2 - chkBox.Height / 2
 .Left = c.Left + c.Width / 8 - chkBox.Width / 2
 'Set the linked cell to the cell with the checkbox
 .LinkedCell = c.Offset(0, 0).Address(external:=True)
 'Set the width of the box
 .Width = 25
 'Enable the checkBox to be used when worksheet protection applied
 .Locked = False
 'Set the name and caption
 .Caption = ""
 .Name = c.Address
 End With
Next c
End Sub
