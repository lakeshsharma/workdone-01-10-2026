# ============================================================================
#  EMBEDDED WPF USER INTERFACE  (was UI\MainWindow.xaml)
# ============================================================================
$script:MainWindowXaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Foreman"
    Height="800"
    Width="1180"
    MinHeight="500"
    MinWidth="1000"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanResize"
    Background="#F5F7FB"
    FontFamily="Segoe UI">

    <Window.Resources>

        <!-- App logo: a "network hub" (one tool linking many servers) drawn as a
             pure vector so it serves both the header and the window/taskbar icon
             with no image files. -->
        <LinearGradientBrush x:Key="LogoBrush" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#2563EB" Offset="0"/>
            <GradientStop Color="#4F46E5" Offset="0.55"/>
            <GradientStop Color="#7C3AED" Offset="1"/>
        </LinearGradientBrush>
        <!-- Colored, transparent hexagon-network mark (no square tile). Used for
             the window / taskbar / EXE icon. -->
        <DrawingImage x:Key="AppLogo">
            <DrawingImage.Drawing>
                <DrawingGroup>
                    <GeometryDrawing>
                        <GeometryDrawing.Pen>
                            <Pen Thickness="1.6" Brush="{StaticResource LogoBrush}"><Pen.DashStyle><DashStyle Dashes="1,2.5"/></Pen.DashStyle></Pen>
                        </GeometryDrawing.Pen>
                        <GeometryDrawing.Geometry><EllipseGeometry Center="50,50" RadiusX="43" RadiusY="43"/></GeometryDrawing.Geometry>
                    </GeometryDrawing>
                    <GeometryDrawing>
                        <GeometryDrawing.Pen>
                            <Pen Thickness="3.5" Brush="{StaticResource LogoBrush}" StartLineCap="Round" EndLineCap="Round" LineJoin="Round"/>
                        </GeometryDrawing.Pen>
                        <GeometryDrawing.Geometry>
                            <GeometryGroup>
                                <LineGeometry StartPoint="50,16" EndPoint="79,33"/>
                                <LineGeometry StartPoint="79,33" EndPoint="79,67"/>
                                <LineGeometry StartPoint="79,67" EndPoint="50,84"/>
                                <LineGeometry StartPoint="50,84" EndPoint="21,67"/>
                                <LineGeometry StartPoint="21,67" EndPoint="21,33"/>
                                <LineGeometry StartPoint="21,33" EndPoint="50,16"/>
                                <LineGeometry StartPoint="50,50" EndPoint="50,16"/>
                                <LineGeometry StartPoint="50,50" EndPoint="79,33"/>
                                <LineGeometry StartPoint="50,50" EndPoint="79,67"/>
                                <LineGeometry StartPoint="50,50" EndPoint="50,84"/>
                                <LineGeometry StartPoint="50,50" EndPoint="21,67"/>
                                <LineGeometry StartPoint="50,50" EndPoint="21,33"/>
                            </GeometryGroup>
                        </GeometryDrawing.Geometry>
                    </GeometryDrawing>
                    <GeometryDrawing Brush="{StaticResource LogoBrush}">
                        <GeometryDrawing.Geometry>
                            <GeometryGroup>
                                <EllipseGeometry Center="50,16" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="79,33" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="79,67" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="50,84" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="21,67" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="21,33" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="50,50" RadiusX="11" RadiusY="11"/>
                            </GeometryGroup>
                        </GeometryDrawing.Geometry>
                    </GeometryDrawing>
                    <GeometryDrawing Brush="#FFFFFF">
                        <GeometryDrawing.Geometry><EllipseGeometry Center="50,50" RadiusX="4" RadiusY="4"/></GeometryDrawing.Geometry>
                    </GeometryDrawing>
                </DrawingGroup>
            </DrawingImage.Drawing>
        </DrawingImage>

        <!-- White rendition of the same mark, for the coloured app header. -->
        <DrawingImage x:Key="AppLogoWhite">
            <DrawingImage.Drawing>
                <DrawingGroup>
                    <GeometryDrawing>
                        <GeometryDrawing.Pen>
                            <Pen Thickness="1.6" Brush="#FFFFFF"><Pen.DashStyle><DashStyle Dashes="1,2.5"/></Pen.DashStyle></Pen>
                        </GeometryDrawing.Pen>
                        <GeometryDrawing.Geometry><EllipseGeometry Center="50,50" RadiusX="43" RadiusY="43"/></GeometryDrawing.Geometry>
                    </GeometryDrawing>
                    <GeometryDrawing>
                        <GeometryDrawing.Pen>
                            <Pen Thickness="3.5" Brush="#FFFFFF" StartLineCap="Round" EndLineCap="Round" LineJoin="Round"/>
                        </GeometryDrawing.Pen>
                        <GeometryDrawing.Geometry>
                            <GeometryGroup>
                                <LineGeometry StartPoint="50,16" EndPoint="79,33"/>
                                <LineGeometry StartPoint="79,33" EndPoint="79,67"/>
                                <LineGeometry StartPoint="79,67" EndPoint="50,84"/>
                                <LineGeometry StartPoint="50,84" EndPoint="21,67"/>
                                <LineGeometry StartPoint="21,67" EndPoint="21,33"/>
                                <LineGeometry StartPoint="21,33" EndPoint="50,16"/>
                                <LineGeometry StartPoint="50,50" EndPoint="50,16"/>
                                <LineGeometry StartPoint="50,50" EndPoint="79,33"/>
                                <LineGeometry StartPoint="50,50" EndPoint="79,67"/>
                                <LineGeometry StartPoint="50,50" EndPoint="50,84"/>
                                <LineGeometry StartPoint="50,50" EndPoint="21,67"/>
                                <LineGeometry StartPoint="50,50" EndPoint="21,33"/>
                            </GeometryGroup>
                        </GeometryDrawing.Geometry>
                    </GeometryDrawing>
                    <GeometryDrawing Brush="#FFFFFF">
                        <GeometryDrawing.Geometry>
                            <GeometryGroup>
                                <EllipseGeometry Center="50,16" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="79,33" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="79,67" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="50,84" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="21,67" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="21,33" RadiusX="6.5" RadiusY="6.5"/>
                                <EllipseGeometry Center="50,50" RadiusX="11" RadiusY="11"/>
                            </GeometryGroup>
                        </GeometryDrawing.Geometry>
                    </GeometryDrawing>
                    <GeometryDrawing Brush="{StaticResource LogoBrush}">
                        <GeometryDrawing.Geometry><EllipseGeometry Center="50,50" RadiusX="4.5" RadiusY="4.5"/></GeometryDrawing.Geometry>
                    </GeometryDrawing>
                </DrawingGroup>
            </DrawingImage.Drawing>
        </DrawingImage>

        <!-- Main colors - modern indigo/blue palette (Kradle / Workbench family) -->
        <SolidColorBrush x:Key="PrimaryBrush" Color="#2563EB"/>
        <SolidColorBrush x:Key="PrimaryDarkBrush" Color="#1E3A8A"/>
        <SolidColorBrush x:Key="AccentBrush" Color="#4F46E5"/>
        <SolidColorBrush x:Key="SuccessBrush" Color="#16A34A"/>
        <SolidColorBrush x:Key="DangerBrush" Color="#DC2626"/>
        <SolidColorBrush x:Key="WarningBrush" Color="#D97706"/>
        <SolidColorBrush x:Key="CardBrush" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#E2E8F0"/>
        <SolidColorBrush x:Key="TextBrush" Color="#0F172A"/>
        <SolidColorBrush x:Key="MutedTextBrush" Color="#64748B"/>
        <SolidColorBrush x:Key="SelectedTabBgBrush" Color="#EEF2FF"/>

        <!-- Header gradient: blue -> violet, like the Kradle Config Builder header -->
        <LinearGradientBrush x:Key="HeaderGradientBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#2563EB" Offset="0"/>
            <GradientStop Color="#4F46E5" Offset="0.55"/>
            <GradientStop Color="#7C3AED" Offset="1"/>
        </LinearGradientBrush>

        <!-- Default text -->
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>

        <!-- Textbox style -->
        <Style TargetType="TextBox">
            <Setter Property="Height" Value="26"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="6,2"/>
            <Setter Property="Margin" Value="3"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Password box style -->
        <Style TargetType="PasswordBox">
            <Setter Property="Height" Value="26"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="6,2"/>
            <Setter Property="Margin" Value="3"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- ComboBox style -->
        <Style TargetType="ComboBox">
            <Setter Property="Height" Value="26"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="6,2"/>
            <Setter Property="Margin" Value="3"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
        </Style>

        <!-- Primary action buttons -->
        <Style x:Key="PrimaryButtonStyle" TargetType="Button">
            <Setter Property="Height" Value="28"/>
            <Setter Property="MinWidth" Value="104"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="Padding" Value="12,3"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                            Background="{TemplateBinding Background}"
                            CornerRadius="6"
                            Padding="{TemplateBinding Padding}">
                            <ContentPresenter
                                HorizontalAlignment="Center"
                                VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#CBD5E1"/>
                    <Setter Property="Foreground" Value="#64748B"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Green buttons -->
        <Style x:Key="SuccessButtonStyle"
               TargetType="Button"
               BasedOn="{StaticResource PrimaryButtonStyle}">
            <Setter Property="Background" Value="{StaticResource SuccessBrush}"/>
        </Style>

        <!-- Red buttons -->
        <Style x:Key="DangerButtonStyle"
               TargetType="Button"
               BasedOn="{StaticResource PrimaryButtonStyle}">
            <Setter Property="Background" Value="{StaticResource DangerBrush}"/>
        </Style>

        <!-- Secondary buttons -->
        <Style x:Key="SecondaryButtonStyle"
               TargetType="Button"
               BasedOn="{StaticResource PrimaryButtonStyle}">
            <Setter Property="Background" Value="#475569"/>
        </Style>

        <!-- GroupBox cards -->
        <Style TargetType="GroupBox">
            <Setter Property="Margin" Value="5"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Background" Value="{StaticResource CardBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource PrimaryDarkBrush}"/>
        </Style>

        <!-- Tab styling: a "step dot" before each label (Kradle wizard style) -->
        <Style TargetType="TabItem">
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource MutedTextBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="tabBd" Background="Transparent" CornerRadius="8" Padding="14,7" Margin="2,0,2,0">
                            <StackPanel Orientation="Horizontal">
                                <Ellipse x:Name="tabDot" Width="11" Height="11" Margin="0,0,8,0"
                                         Stroke="{StaticResource MutedTextBrush}" StrokeThickness="2" Fill="Transparent"/>
                                <ContentPresenter ContentSource="Header" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="tabBd" Property="Background" Value="{StaticResource SelectedTabBgBrush}"/>
                                <Setter TargetName="tabDot" Property="Fill" Value="{StaticResource PrimaryBrush}"/>
                                <Setter TargetName="tabDot" Property="Stroke" Value="{StaticResource PrimaryBrush}"/>
                                <Setter Property="Foreground" Value="{StaticResource PrimaryBrush}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="tabBd" Property="Background" Value="#F1F5F9"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Toggle switch (styled CheckBox) - iOS/Kradle-style on/off pill -->
        <Style x:Key="ToggleSwitchStyle" TargetType="CheckBox">
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal" Background="Transparent">
                            <Border x:Name="track" Width="40" Height="21" CornerRadius="11" Background="#CBD5E1" VerticalAlignment="Center">
                                <Ellipse x:Name="thumb" Width="15" Height="15" Fill="White" HorizontalAlignment="Left" Margin="3,0,0,0"/>
                            </Border>
                            <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="track" Property="Background" Value="{StaticResource PrimaryBrush}"/>
                                <Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="thumb" Property="Margin" Value="0,0,3,0"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="track" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Health pill button (Resources column): coloured by the row's Health value
             (green OK / amber CAUTION / red CRITICAL / grey when not yet checked) -->
        <Style x:Key="HealthButtonStyle" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Height" Value="24"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Background" Value="{StaticResource MutedTextBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="hb" Background="{TemplateBinding Background}" CornerRadius="5" Padding="10,2">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="hb" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <DataTrigger Binding="{Binding Health}" Value="OK">
                    <Setter Property="Background" Value="{StaticResource SuccessBrush}"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding Health}" Value="CAUTION">
                    <Setter Property="Background" Value="{StaticResource WarningBrush}"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding Health}" Value="CRITICAL">
                    <Setter Property="Background" Value="{StaticResource DangerBrush}"/>
                </DataTrigger>
            </Style.Triggers>
        </Style>

        <!-- Multi-select target picker: a ComboBox-looking ToggleButton that opens a
             checkbox popup (pick several servers). -->
        <Style x:Key="TargetPickerStyle" TargetType="ToggleButton">
            <Setter Property="Height" Value="26"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToggleButton">
                        <Border x:Name="tp" Background="{TemplateBinding Background}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="8,0">
                            <DockPanel>
                                <TextBlock DockPanel.Dock="Right" Text="&#9662;" Margin="6,0,0,0" VerticalAlignment="Center" Foreground="{StaticResource MutedTextBrush}"/>
                                <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Left"/>
                            </DockPanel>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="tp" Property="BorderBrush" Value="{StaticResource PrimaryBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Subtle footer buttons (on the dark footer bar) -->
        <Style x:Key="FooterButtonStyle" TargetType="Button">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="Background" Value="#334155"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Height" Value="20"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="Margin" Value="8,0,0,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="fb" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="fb" Property="Background" Value="#475569"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Target-server selector label -->
        <Style x:Key="TargetLabelStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource PrimaryDarkBrush}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
        </Style>

    </Window.Resources>

    <Grid>

        <Grid.RowDefinitions>
            <RowDefinition Height="58"/>
            <RowDefinition Height="*"/>
			<RowDefinition Height="28"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border
            Grid.Row="0"
            Background="{StaticResource HeaderGradientBrush}"
            Padding="18,7">

            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Image Source="{StaticResource AppLogoWhite}" Width="48" Height="48" Margin="0,0,14,0"
                           VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality"
                           SnapsToDevicePixels="True"/>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock
                            x:Name="TxtAppTitle"
                            Text="Foreman"
                            Foreground="White"
                            FontSize="20"
                            FontWeight="Bold"/>

                        <TextBlock
                            Text="OneLink remote deployment, database and service management"
                            Foreground="#DBE4FF"
                            FontSize="11"
                            Margin="0,2,0,0"/>
                    </StackPanel>
                </StackPanel>

                <Border
                    Grid.Column="1"
                    Background="#33FFFFFF"
                    CornerRadius="12"
                    Padding="12,5"
                    VerticalAlignment="Center">

                    <TextBlock
                        x:Name="TxtAppBadge"
                        Text="Aristocrat Customer Success"
                        Foreground="White"
                        FontSize="11"
                        FontWeight="SemiBold"/>
                </Border>
            </Grid>
        </Border>

        <!-- Scrollable middle region (header stays pinned above, footer below) -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

        <!-- Servers manager -->
        <Border
            Grid.Row="0"
            Margin="14,12,14,6"
            Padding="10"
            Background="White"
            BorderBrush="{StaticResource BorderBrush}"
            BorderThickness="1"
            CornerRadius="6">

            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="150"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Toolbar: title + row actions + config import/export -->
                <Grid Grid.Row="0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="Servers" FontSize="14" FontWeight="Bold" Foreground="{StaticResource PrimaryDarkBrush}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                        <Button x:Name="BtnAddServer" Content="Add Row" Style="{StaticResource PrimaryButtonStyle}"/>
                        <Button x:Name="BtnRemoveServer" Content="Clear All" Style="{StaticResource SecondaryButtonStyle}"
                                ToolTip="Remove every server row from the list (asks to confirm). To remove a single server, right-click its row."/>
                        <Button x:Name="BtnSameCreds" Content="Same login for all" Style="{StaticResource SecondaryButtonStyle}"
                                ToolTip="Set one username/password and apply it to every server row (or the selected rows)"/>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button x:Name="BtnTemplateConfig" Content="Template" Style="{StaticResource SecondaryButtonStyle}"
                                ToolTip="Save a blank fill-in Excel template (tabs: Servers / Database / Package / Certificate / Service) with every option"/>
                        <Button x:Name="BtnImportConfig" Content="Import Config" Style="{StaticResource SecondaryButtonStyle}"/>
                        <Button x:Name="BtnExportConfig" Content="Export Config" Style="{StaticResource SecondaryButtonStyle}"
                                ToolTip="Save the current config as a colour Excel workbook (re-importable)"/>
                    </StackPanel>
                </Grid>

                <TextBlock
                    Grid.Row="1"
                    Margin="2,8,0,4"
                    Foreground="{StaticResource MutedTextBrush}"
                    FontSize="12"
                    Text="Type IP, Port and Username in each row; click the Password and Roles cells to set them; then Connect All."/>

                <!-- Editable server grid -->
                <DataGrid
                    x:Name="ServerGrid"
                    Grid.Row="2"
                    AutoGenerateColumns="False"
                    CanUserAddRows="False"
                    CanUserDeleteRows="False"
                    HeadersVisibility="Column"
                    SelectionMode="Extended"
                    GridLinesVisibility="Horizontal"
                    Background="White"
                    RowBackground="White"
                    AlternatingRowBackground="#F8FAFC"
                    BorderBrush="{StaticResource BorderBrush}"
                    BorderThickness="1"
                    CanUserResizeRows="False"
                    RowHeight="30"
                    ColumnHeaderHeight="28"
                    HorizontalScrollBarVisibility="Auto"
                    FontWeight="Normal">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Server IP / Host" Binding="{Binding Host, UpdateSourceTrigger=LostFocus}" Width="2*"/>
                        <DataGridTextColumn Header="Port" Binding="{Binding Port, UpdateSourceTrigger=LostFocus}" Width="55"/>
                        <DataGridTextColumn Header="Username" Binding="{Binding Username, UpdateSourceTrigger=LostFocus}" Width="1.4*"/>
                        <DataGridTemplateColumn Header="Password" Width="120" IsReadOnly="True">
                            <DataGridTemplateColumn.CellTemplate>
                                <DataTemplate>
                                    <Button Content="{Binding PasswordDisplay}" Tag="Password" Margin="2" Padding="6,2" Cursor="Hand"/>
                                </DataTemplate>
                            </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="Roles (mark)" Width="2.4*" IsReadOnly="True">
                            <DataGridTemplateColumn.CellTemplate>
                                <DataTemplate>
                                    <Button Content="{Binding RolesDisplay}" Tag="Roles" Margin="2" Padding="6,2" Cursor="Hand" HorizontalContentAlignment="Left"/>
                                </DataTemplate>
                            </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="OneLink Services" Width="2*" IsReadOnly="True">
                            <DataGridTemplateColumn.CellTemplate>
                                <DataTemplate>
                                    <DockPanel LastChildFill="True">
                                        <Button DockPanel.Dock="Right" Tag="RefreshServices" Content="&#x21BB;"
                                                Width="22" Height="20" Padding="0" Margin="4,1,2,1" FontSize="12" Cursor="Hand"
                                                ToolTip="Re-check the OneLink services installed on this server"/>
                                        <TextBlock Text="{Binding ServicesDisplay}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="2,0,0,0"/>
                                    </DockPanel>
                                </DataTemplate>
                            </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="Resources" Width="96" IsReadOnly="True">
                            <DataGridTemplateColumn.CellTemplate>
                                <DataTemplate>
                                    <Button Tag="Resources" Style="{StaticResource HealthButtonStyle}"
                                            Content="{Binding Health}"
                                            Margin="2"
                                            ToolTip="Show disk partitions, memory and CPU (green = OK, amber = caution, red = critical)"/>
                                </DataTemplate>
                            </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="Status" Binding="{Binding Status}" IsReadOnly="True" Width="2*"/>
                        <DataGridTemplateColumn Header="Actions" Width="160" IsReadOnly="True">
                            <DataGridTemplateColumn.CellTemplate>
                                <DataTemplate>
                                    <StackPanel Orientation="Horizontal">
                                        <Button Tag="Console" Content="Console" Margin="2" Padding="8,2" Cursor="Hand"
                                                ToolTip="Open an SSH command console on THIS server (run touch, chmod, systemctl status, ...)."/>
                                        <Button Tag="EditFile" Content="Edit File" Margin="2" Padding="8,2" Cursor="Hand"
                                                ToolTip="Open and edit a file on this server."/>
                                    </StackPanel>
                                </DataTemplate>
                            </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                    </DataGrid.Columns>
                </DataGrid>

                <!-- Connect controls + summary -->
                <Grid Grid.Row="3" Margin="0,8,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Button x:Name="BtnConnect"    Grid.Column="0" Content="Connect All"    Style="{StaticResource SuccessButtonStyle}"/>
                    <Button x:Name="BtnDisconnect" Grid.Column="1" Content="Disconnect All" Style="{StaticResource DangerButtonStyle}" IsEnabled="False"/>

                    <TextBlock Grid.Column="2" Text="Status:" Margin="16,0,8,0" FontWeight="SemiBold" Foreground="{StaticResource PrimaryDarkBrush}" VerticalAlignment="Center"/>

                    <Border Grid.Column="3" Background="#FEE2E2" CornerRadius="5" Padding="10,6" Margin="5" VerticalAlignment="Center">
                        <TextBlock
                            x:Name="TxtConnectionStatus"
                            Text="No servers added"
                            Foreground="{StaticResource DangerBrush}"
                            FontWeight="Bold"/>
                    </Border>
                </Grid>
            </Grid>
        </Border>

        <!-- Operations -->
        <Grid Grid.Row="1" Margin="18,8,18,4">

            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,6">
                <Border
                    Width="5"
                    Height="20"
                    Background="{StaticResource AccentBrush}"
                    CornerRadius="2"
                    Margin="0,0,8,0"/>

                <TextBlock
                    Text="Operations"
                    FontSize="16"
                    FontWeight="Bold"
                    Foreground="{StaticResource PrimaryDarkBrush}"/>
            </StackPanel>

            <TabControl Grid.Row="1" x:Name="OperationTabs" Height="470">

                <!-- Database tab -->
                <TabItem Header="Database">
                    <ScrollViewer
                        VerticalScrollBarVisibility="Auto"
                        HorizontalScrollBarVisibility="Disabled">

                        <Grid Margin="12" MinHeight="390">

                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <!-- One target for the whole Database tab (Database master / slave only) -->
                        <StackPanel Grid.Row="0">
                            <StackPanel Orientation="Horizontal" Margin="4,0,4,6">
                                <TextBlock Text="Target server (Database master / slave):" Style="{StaticResource TargetLabelStyle}"/>
                                <ToggleButton x:Name="BtnTargetDb" MinWidth="220" MaxWidth="360" Content="No DB server" Style="{StaticResource TargetPickerStyle}"
                                              ToolTip="Pick one or more Database-marked servers to act on"/>
                                <Popup x:Name="PopTargetDb" StaysOpen="False" Placement="Bottom" PlacementTarget="{Binding ElementName=BtnTargetDb}" IsOpen="{Binding IsChecked, ElementName=BtnTargetDb, Mode=TwoWay}">
                                    <Border Background="White" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,2,0,0">
                                        <ScrollViewer MaxHeight="240" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="PnlTargetDb" MinWidth="200"/></ScrollViewer>
                                    </Border>
                                </Popup>
                            </StackPanel>

                            <StackPanel Orientation="Horizontal" Margin="4,0,4,10">
                                <TextBlock Text="MySQL service:" Style="{StaticResource TargetLabelStyle}"/>
                                <Button x:Name="BtnMysqlRestart" Content="Restart" Style="{StaticResource PrimaryButtonStyle}" MinWidth="90"/>
                                <Button x:Name="BtnMysqlStop" Content="Stop" Style="{StaticResource DangerButtonStyle}" MinWidth="90"/>
                                <Button x:Name="BtnMysqlStatus" Content="Get Status of Database" Style="{StaticResource SecondaryButtonStyle}"/>
                                <Border CornerRadius="5" Padding="12,4" Margin="10,0,0,0" VerticalAlignment="Center" Background="#F1F5F9">
                                    <TextBlock x:Name="TxtMysqlStatus" Text="Status: unknown" FontWeight="Bold" Foreground="{StaticResource MutedTextBrush}"/>
                                </Border>
                            </StackPanel>
                        </StackPanel>

                        <Grid Grid.Row="1">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- LEFT COLUMN: Create Database, then Create Database User -->
                            <StackPanel Grid.Column="0">

                                <GroupBox Header="Create Database">
                                    <Grid Margin="10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="135"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Text="Database Name:"/>
                                        <TextBox x:Name="TxtDatabaseName" Grid.Row="0" Grid.Column="1" ToolTip="Database to create"/>

                                        <Button x:Name="BtnCreateDatabase" Grid.Row="1" Grid.ColumnSpan="2"
                                                Content="Create Database" Style="{StaticResource PrimaryButtonStyle}"
                                                HorizontalAlignment="Right" Margin="6,14,6,6"/>
                                    </Grid>
                                </GroupBox>

                                <GroupBox Header="Create Database User">
                                    <Grid Margin="10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="135"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Text="Username:"/>
                                        <TextBox x:Name="TxtDbUser" Grid.Row="0" Grid.Column="1" ToolTip="New MySQL username"/>

                                        <TextBlock Grid.Row="1" Text="Password:"/>
                                        <PasswordBox x:Name="PwdDbUser" Grid.Row="1" Grid.Column="1" ToolTip="Password for the new MySQL user"/>

                                        <TextBlock Grid.Row="2" Text="Re-type Password:"/>
                                        <PasswordBox x:Name="PwdDbUserConfirm" Grid.Row="2" Grid.Column="1" ToolTip="Re-enter the password to confirm it matches"/>

                                        <CheckBox x:Name="ChkSetAllowedIp" Style="{StaticResource ToggleSwitchStyle}" Grid.Row="3" Content="Allowed IP:" VerticalAlignment="Center"
                                                  ToolTip="Leave UNCHECKED to use the default (% = any host). Check it to lock in a specific client host/IP."/>
                                        <ComboBox x:Name="CmbDbUserIp" Grid.Row="3" Grid.Column="1" IsEditable="True" IsEnabled="False"
                                                  ToolTip="Client host allowed to connect. Pick % (any host), localhost (local-only), the target server IP, or type one. Blank = % (works locally AND remotely). Enabled only when 'Allowed IP' is checked."/>

                                        <Button x:Name="BtnCreateDbUser" Grid.Row="4" Grid.ColumnSpan="2"
                                                Content="Create DB User" Style="{StaticResource PrimaryButtonStyle}"
                                                HorizontalAlignment="Right" Margin="6,14,6,6"/>
                                    </Grid>
                                </GroupBox>

                                <GroupBox Header="InnoDB Buffer Pool Size">
                                    <Grid Margin="10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="135"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock x:Name="TxtInnodbInfo" Grid.Row="0" Grid.ColumnSpan="2" TextWrapping="Wrap"
                                                   Foreground="{StaticResource MutedTextBrush}" Margin="0,0,0,8"
                                                   Text="Click 'Check Current / Recommended' to load the current buffer pool size and RAM for the target server."/>

                                        <Button x:Name="BtnInnodbCheck" Grid.Row="1" Grid.ColumnSpan="2"
                                                Content="Check Current / Recommended" Style="{StaticResource SecondaryButtonStyle}"
                                                HorizontalAlignment="Right" Margin="6,0,6,10"/>

                                        <TextBlock Grid.Row="2" Text="New Size:"/>
                                        <TextBox x:Name="TxtInnodbSize" Grid.Row="2" Grid.Column="1"
                                                 ToolTip="e.g. 1.5G, 500M, 2GB, 1.5g, 500mb (case-insensitive; G/GB or M/MB)"/>

                                        <Border x:Name="BrdInnodbWarn" Grid.Row="3" Grid.ColumnSpan="2" CornerRadius="5" Padding="10,6" Margin="0,8,0,0" Background="#F1F5F9">
                                            <TextBlock x:Name="TxtInnodbWarn" TextWrapping="Wrap" Foreground="{StaticResource MutedTextBrush}"
                                                       Text="Enter a size (e.g. 1.5G, 500M) and click 'Check Current / Recommended' to compare it against this server's RAM."/>
                                        </Border>

                                        <Button x:Name="BtnInnodbApply" Grid.Row="4" Grid.ColumnSpan="2"
                                                Content="Apply (Restarts MySQL)" Style="{StaticResource PrimaryButtonStyle}"
                                                HorizontalAlignment="Right" Margin="6,14,6,6"/>
                                    </Grid>
                                </GroupBox>

                                <!-- Run a .sql script already on the target server (nmenu 'ndb_run' equivalent) -->
                                <GroupBox Header="Run SQL Script">
                                    <Grid Margin="10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="135"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Text="Search (name contains):"/>
                                        <TextBox x:Name="TxtSqlSearchTerm" Grid.Row="0" Grid.Column="1"
                                                 ToolTip="e.g. 'test' finds test.sql, TEST.sql, Test_v2.sql, etc. anywhere on the target server."/>

                                        <Button x:Name="BtnSqlSearch" Grid.Row="1" Grid.ColumnSpan="2"
                                                Content="Search" Style="{StaticResource SecondaryButtonStyle}"
                                                HorizontalAlignment="Right" Margin="6,0,6,10"/>

                                        <TextBlock Grid.Row="2" Text="Found scripts:"/>
                                        <ComboBox x:Name="CmbSqlScriptFound" Grid.Row="2" Grid.Column="1"
                                                  ToolTip="Pick one of the matching .sql files found on the target server."/>

                                        <TextBlock x:Name="TxtSqlSearchStatus" Grid.Row="3" Grid.ColumnSpan="2" Text=""
                                                   Foreground="{StaticResource MutedTextBrush}" TextWrapping="Wrap" Margin="0,8,0,0"/>

                                        <Button x:Name="BtnRunSqlScript" Grid.Row="4" Grid.ColumnSpan="2"
                                                Content="Run Script" Style="{StaticResource DangerButtonStyle}"
                                                HorizontalAlignment="Right" Margin="6,14,6,6"/>
                                    </Grid>
                                </GroupBox>
                            </StackPanel>

                            <!-- RIGHT COLUMN: Grant, then Backup / Restore -->
                            <StackPanel Grid.Column="1">

                                <GroupBox Header="Grant Admin Privileges">
                                    <Grid Margin="10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="150"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Text="User:"/>
                                        <ComboBox x:Name="CmbGrantUser" Grid.Row="0" Grid.Column="1" IsEditable="True"
                                                  ToolTip="MySQL user. Use 'Refresh users / databases' to load them from the target, or type one."/>

                                        <TextBlock Grid.Row="1" Text="Database:"/>
                                        <ComboBox x:Name="CmbGrantDb" Grid.Row="1" Grid.Column="1" IsEditable="True"
                                                  ToolTip="Database to grant on. Use 'Refresh users / databases' to load them from the target, or type one."/>

                                        <TextBlock Grid.Row="2" Text="Account host / IP:"/>
                                        <ComboBox x:Name="CmbGrantHost" Grid.Row="2" Grid.Column="1" IsEditable="True" Text="%"
                                                  ToolTip="Use the same host as the MySQL account: %, localhost, or the IP supplied when creating the user."/>
                                        <TextBlock Grid.Row="3" Text="Password (Optional):"/>
                                        <PasswordBox x:Name="PwdGrant" Grid.Row="3" Grid.Column="1"
                                                     ToolTip="OPTIONAL - use at your own risk. Leave BLANK to grant without touching the password. If you set it, a WRONG value WILL overwrite the user's real password."/>

                                        <TextBlock Grid.Row="4" Text="Re-type Password:"/>
                                        <PasswordBox x:Name="PwdGrantConfirm" Grid.Row="4" Grid.Column="1"
                                                     ToolTip="Re-enter the optional password to confirm it matches (leave blank if you left Password blank)."/>

                                        <Button x:Name="BtnRefreshDbLists" Grid.Row="5" Grid.ColumnSpan="2"
                                                Content="Refresh users / databases" Style="{StaticResource SecondaryButtonStyle}"
                                                HorizontalAlignment="Right" Margin="6,12,6,4"/>

                                        <Button x:Name="BtnGrantPrivileges" Grid.Row="6" Grid.ColumnSpan="2"
                                                Content="Grant Admin Privileges" Style="{StaticResource SuccessButtonStyle}"
                                                HorizontalAlignment="Right" Margin="6,4,6,6"/>
                                    </Grid>
                                </GroupBox>

                                <!-- BACKUP (export a dump to a destination) -->
                                <GroupBox Header="Backup (Export)">
                                    <Grid Margin="10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="150"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Text="Database:"/>
                                        <ComboBox x:Name="CmbExportDb" Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="2" IsEditable="True" Text="onelink"
                                                  ToolTip="Database to back up. Use 'Refresh users / databases' to load them from the target, or type one."/>

                                        <TextBlock Grid.Row="1" Text="Destination:"/>
                                        <ComboBox x:Name="CmbExportDest" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2"
                                                  ToolTip="Where to write the backup. Server = a path on the target VM; Local Windows = this PC; Network location = a UNC share (with credentials).">
                                            <ComboBoxItem Content="Server (path on the VM)" IsSelected="True"/>
                                            <ComboBoxItem Content="Local Windows (this PC)"/>
                                            <ComboBoxItem Content="Network location (share)"/>
                                        </ComboBox>

                                        <StackPanel x:Name="ExportNetRow" Grid.Row="2" Grid.ColumnSpan="3" Orientation="Horizontal" Visibility="Collapsed" Margin="0,4,0,0">
                                            <TextBlock Text="Network user / pass:" Width="150" VerticalAlignment="Center"/>
                                            <TextBox x:Name="TxtExportNetUser" Width="150" ToolTip="OPTIONAL. Username for the network share (e.g. DOMAIN\\user)."/>
                                            <PasswordBox x:Name="PwdExportNetPass" Width="150" Margin="8,0,0,0" ToolTip="OPTIONAL. Password for the network share."/>
                                        </StackPanel>

                                        <TextBlock Grid.Row="3" Text="Backup file:"/>
                                        <TextBox x:Name="TxtExportFile" Grid.Row="3" Grid.Column="1" Text="/mysqldata/ndb_export.sql.gz"
                                                 ToolTip="Where to write the dump. Server: an absolute Linux path. Local Windows: a path on THIS PC (Browse). Network: a UNC path (e.g. \\server\share\db.sql.gz)."/>
                                        <Button x:Name="BtnBrowseExport" Grid.Row="3" Grid.Column="2" Content="Browse..." Style="{StaticResource SecondaryButtonStyle}" Margin="6,0,0,0"/>

                                        <TextBlock x:Name="TxtExportStatus" Grid.Row="4" Grid.ColumnSpan="3" Text="" Foreground="{StaticResource MutedTextBrush}" TextWrapping="Wrap" Margin="0,6,0,0"/>

                                        <StackPanel Grid.Row="5" Grid.ColumnSpan="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,4">
                                            <Button x:Name="BtnStopExport" Content="Stop" Style="{StaticResource DangerButtonStyle}" IsEnabled="False"/>
                                            <Button x:Name="BtnExportDb" Content="Export DB" Style="{StaticResource SuccessButtonStyle}"/>
                                        </StackPanel>
                                    </Grid>
                                </GroupBox>

                                <!-- RESTORE (import a dump from a source) -->
                                <GroupBox Header="Restore (Import)">
                                    <Grid Margin="10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="150"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Text="Database:"/>
                                        <ComboBox x:Name="CmbImportDb" Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="2" IsEditable="True" Text="onelink"
                                                  ToolTip="Database to restore INTO. Use 'Refresh users / databases' to load them from the target, or type one."/>

                                        <TextBlock Grid.Row="1" Text="Source:"/>
                                        <ComboBox x:Name="CmbImportSrc" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2"
                                                  ToolTip="Where the backup file comes FROM. Server = a path already on the target VM; Local Windows = this PC; Network location = a UNC share; Another VM = pull it from a different VM over SSH.">
                                            <ComboBoxItem Content="Server (path on the VM)" IsSelected="True"/>
                                            <ComboBoxItem Content="Local Windows (this PC)"/>
                                            <ComboBoxItem Content="Network location (share)"/>
                                            <ComboBoxItem Content="Another VM (SSH)"/>
                                        </ComboBox>

                                        <StackPanel x:Name="ImportNetRow" Grid.Row="2" Grid.ColumnSpan="3" Orientation="Horizontal" Visibility="Collapsed" Margin="0,4,0,0">
                                            <TextBlock Text="Network user / pass:" Width="150" VerticalAlignment="Center"/>
                                            <TextBox x:Name="TxtImportNetUser" Width="150" ToolTip="OPTIONAL. Username for the network share."/>
                                            <PasswordBox x:Name="PwdImportNetPass" Width="150" Margin="8,0,0,0" ToolTip="OPTIONAL. Password for the network share."/>
                                        </StackPanel>

                                        <StackPanel x:Name="ImportVmRow" Grid.Row="3" Grid.ColumnSpan="3" Orientation="Horizontal" Visibility="Collapsed" Margin="0,4,0,0">
                                            <TextBlock Text="VM host / user / pass:" Width="150" VerticalAlignment="Center"/>
                                            <TextBox x:Name="TxtImportVmHost" Width="120" ToolTip="IP / hostname of the other VM (RHEL or Debian)."/>
                                            <TextBox x:Name="TxtImportVmUser" Width="90" Margin="6,0,0,0" ToolTip="SSH username on the other VM."/>
                                            <PasswordBox x:Name="PwdImportVmPass" Width="90" Margin="6,0,0,0" ToolTip="SSH password on the other VM."/>
                                        </StackPanel>

                                        <TextBlock Grid.Row="4" Text="Backup file:"/>
                                        <TextBox x:Name="TxtImportFile" Grid.Row="4" Grid.Column="1" Text="/mysqldata/ndb_export.sql.gz"
                                                 ToolTip="Path of the backup to restore FROM. Server / Another VM: an absolute Linux path. Local Windows: a path on THIS PC (Browse). Network: a UNC path."/>
                                        <Button x:Name="BtnBrowseImport" Grid.Row="4" Grid.Column="2" Content="Browse..." Style="{StaticResource SecondaryButtonStyle}" Margin="6,0,0,0"/>

                                        <TextBlock x:Name="TxtImportStatus" Grid.Row="5" Grid.ColumnSpan="3" Text="" Foreground="{StaticResource MutedTextBrush}" TextWrapping="Wrap" Margin="0,6,0,0"/>

                                        <StackPanel Grid.Row="6" Grid.ColumnSpan="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,4">
                                            <Button x:Name="BtnStopImport" Content="Stop" Style="{StaticResource DangerButtonStyle}" IsEnabled="False"/>
                                            <Button x:Name="BtnImportDb" Content="Import DB" Style="{StaticResource PrimaryButtonStyle}"/>
                                        </StackPanel>
                                    </Grid>
                                </GroupBox>
                            </StackPanel>
                        </Grid>
                    </Grid>
                </ScrollViewer>
                </TabItem>

                <!-- Package tab -->
                <TabItem Header="Certificates">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <Grid Margin="12" MinHeight="340">
                        <GroupBox Header="Deploy Certificate / License" MinHeight="220" VerticalAlignment="Top">
                          <StackPanel>
                            <StackPanel Orientation="Horizontal" Margin="12,8,12,0">
                                <TextBlock Text="Target server:" Style="{StaticResource TargetLabelStyle}"/>
                                <ToggleButton x:Name="BtnTargetCert" MinWidth="220" MaxWidth="360" Content="All servers" Style="{StaticResource TargetPickerStyle}"
                                              ToolTip="Pick one or more servers to act on"/>
                                <Popup x:Name="PopTargetCert" StaysOpen="False" Placement="Bottom" PlacementTarget="{Binding ElementName=BtnTargetCert}" IsOpen="{Binding IsChecked, ElementName=BtnTargetCert, Mode=TwoWay}">
                                    <Border Background="White" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,2,0,0">
                                        <ScrollViewer MaxHeight="240" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="PnlTargetCert" MinWidth="200"/></ScrollViewer>
                                    </Border>
                                </Popup>
                            </StackPanel>
                            <Grid Margin="12">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="190"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="140"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <TextBlock Grid.Row="0" Text="Cert / License file (local/network):" VerticalAlignment="Center"/>
                                <TextBox x:Name="TxtCertFile" Grid.Row="0" Grid.Column="1"
                                         ToolTip="Local file OR a network path (e.g. \\server\share\file.pem). Accepts certificates AND licenses: .pem .crt .cer .der .cert .ks .jks .p12 .pfx .lic .key ..."/>
                                <Button x:Name="BtnBrowseCert" Grid.Row="0" Grid.Column="2" Content="Browse..."
                                        Style="{StaticResource SecondaryButtonStyle}"/>

                                <CheckBox x:Name="ChkCertNetAuth" Style="{StaticResource ToggleSwitchStyle}" Grid.Row="1" Content="Network login:" VerticalAlignment="Center"
                                          ToolTip="Tick only if the network folder needs a username and password."/>
                                <StackPanel Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Orientation="Horizontal">
                                    <TextBlock Text="User" VerticalAlignment="Center" Margin="0,0,5,0"/>
                                    <TextBox x:Name="TxtCertNetUser" Width="150" IsEnabled="False" ToolTip="Type the USERNAME for the network share (e.g. DOMAIN\\user). Enabled only when 'Network login' is ticked."/>
                                    <TextBlock Text="Password" VerticalAlignment="Center" Margin="12,0,5,0"/>
                                    <PasswordBox x:Name="PwdCertNetPass" Width="150" IsEnabled="False" ToolTip="Type the PASSWORD for the network share. Enabled only when 'Network login' is ticked."/>
                                    <Button x:Name="BtnCertNetTest" Content="Test login" IsEnabled="False" Margin="12,0,0,0"
                                            Style="{StaticResource SecondaryButtonStyle}"
                                            ToolTip="Check whether this username/password can connect to the network file/folder above."/>
                                </StackPanel>

                                <TextBlock Grid.Row="2" Text="Destination (server path):" VerticalAlignment="Center"/>
                                <TextBox x:Name="TxtCertDest" Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2"
                                         ToolTip="Absolute Linux path on the target (RHEL or Debian). End with '/' to keep the original filename, or give a full file path."/>
                                <TextBlock Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="2" Foreground="Gray" FontStyle="Italic"
                                           Text="e.g. /opt/onelink/etc/client.ks   (or a directory like /opt/onelink/ ending in / )"/>

                                <TextBlock Grid.Row="4" Text="Back up existing file to:" VerticalAlignment="Center"
                                           ToolTip="If a file already exists at the destination, Deploy saves a copy of it here FIRST, before overwriting. Nothing is saved if there is no existing file yet."/>
                                <ComboBox x:Name="CmbCertBackupDest" Grid.Row="4" Grid.Column="1" Grid.ColumnSpan="2">
                                    <ComboBoxItem Content="Local Windows (this PC)" IsSelected="True"/>
                                    <ComboBoxItem Content="Server (same VM, alongside the file)"/>
                                    <ComboBoxItem Content="Don't back up"/>
                                </ComboBox>

                                <TextBlock Grid.Row="5" Text="Backup folder:" VerticalAlignment="Center"/>
                                <TextBox x:Name="TxtCertBackupPath" Grid.Row="5" Grid.Column="1"
                                         ToolTip="Where the backup copy goes. For 'Local Windows' this is a folder on this PC (a per-server subfolder is created under it); for 'Server' this is an absolute Linux folder on the target. Pre-filled but fully editable."/>
                                <Button x:Name="BtnCertBackupBrowse" Grid.Row="5" Grid.Column="2" Content="Browse..."
                                        Style="{StaticResource SecondaryButtonStyle}"
                                        ToolTip="Pick a folder on this PC (only used for the 'Local Windows' backup destination)."/>

                                <Separator Grid.Row="6" Grid.ColumnSpan="3" Margin="0,8,0,4"/>

                                <TextBlock Grid.Row="7" Text="Check Status - look for:" VerticalAlignment="Center"/>
                                <ComboBox x:Name="CmbCertType" Grid.Row="7" Grid.Column="1" Grid.ColumnSpan="2"
                                          ToolTip="File type to look for when you click 'List files' on a folder.">
                                    <ComboBoxItem Content="All (certs, keystores, licenses, keys)" IsSelected="True"/>
                                    <ComboBoxItem Content="Certificates (.pem .crt .cer .der .cert .ca .p7b .p7c .csr .crl)"/>
                                    <ComboBoxItem Content="Keystores (.ks .jks .p12 .pfx .keystore .truststore .jceks .bks)"/>
                                    <ComboBoxItem Content="Licenses (.lic .license)"/>
                                    <ComboBoxItem Content="Keys (.key .pk8 .p8)"/>
                                </ComboBox>

                                <TextBlock Grid.Row="8" Text="Folder / file on server:" VerticalAlignment="Center"/>
                                <TextBox x:Name="TxtCertScanPath" Grid.Row="8" Grid.Column="1" Text="/opt/onelink/etc/"
                                         ToolTip="A folder to scan (e.g. /opt/onelink/etc/) or a single file path on the target server."/>
                                <Button x:Name="BtnCertList" Grid.Row="8" Grid.Column="2" Content="List files"
                                        Style="{StaticResource SecondaryButtonStyle}"
                                        ToolTip="Scan that folder on the selected server and list the matching cert/keystore/license files below."/>

                                <TextBlock Grid.Row="9" Text="Found files:" VerticalAlignment="Center"/>
                                <ComboBox x:Name="CmbCertFound" Grid.Row="9" Grid.Column="1" Grid.ColumnSpan="2"
                                          ToolTip="Pick a file found by 'List files', then click 'Check Status'."/>

                                <StackPanel Grid.Row="10" Grid.ColumnSpan="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                                    <Button x:Name="BtnCertStatus" Content="Check Status"
                                            Style="{StaticResource SecondaryButtonStyle}"
                                            ToolTip="Show the details of the file selected in 'Found files' (or type a full file path there and check it)."/>
                                    <Button x:Name="BtnDeployCert" Content="Deploy Certificate"
                                            Style="{StaticResource SuccessButtonStyle}"/>
                                </StackPanel>
                            </Grid>
                            <Border Background="#FEF9C3" CornerRadius="6" Padding="10" Margin="12,0,12,12">
                                <TextBlock TextWrapping="Wrap" Foreground="{StaticResource PrimaryDarkBrush}"
                                           Text="Deploy uploads the selected file (certificate OR license: .pem .crt .cer .der .cert .ks .jks .p12 .pfx .lic .key ...) and installs it at the destination path on each target server. To inspect what's on a server: type a folder in 'Folder / file on server', click 'List files' to find the certs/keystores/licenses, pick one under 'Found files', then click 'Check Status'. If a service must load a new cert (e.g. an appserver keystore), restart it from the Package tab -> Service Installer."/>
                            </Border>
                          </StackPanel>
                        </GroupBox>
                    </Grid>
                    </ScrollViewer>
                </TabItem>

                <!-- Activity Metrics tab - clicks/fields/time captured per activity -->
                <TabItem Header="Package">
                    <ScrollViewer
                        VerticalScrollBarVisibility="Auto"
                        HorizontalScrollBarVisibility="Disabled">

                        <Grid Margin="12" MinHeight="330">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="230"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <GroupBox Grid.Row="0" Grid.Column="1" Header="Package Source (folder of .rpm / .deb packages)">
                                <Grid Margin="14">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="180"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="140"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>

                                    <TextBlock Grid.Row="0" Text="Folder(s) (local or network):" VerticalAlignment="Top" Margin="0,6,0,0"/>
                                    <TextBox
                                        x:Name="TxtPackagePath"
                                        Grid.Row="0"
                                        Grid.Column="1"
                                        TextWrapping="Wrap" AcceptsReturn="False"
                                        ToolTip="One folder, OR several LOCAL folders picked via Browse (shown separated by ' ; '), OR a single network path (e.g. \\server\share\...). Every subfolder under each one is searched too. You can also type or paste a single path directly."/>
                                    <Button
                                        x:Name="BtnBrowsePackage"
                                        Grid.Row="0"
                                        Grid.Column="2"
                                        Content="Browse..."
                                        VerticalAlignment="Top"
                                        Style="{StaticResource SecondaryButtonStyle}"
                                        ToolTip="Tick one or more folders (any drive, any branch) in the picker, then click OK - all of them are added at once."/>

                                    <CheckBox x:Name="ChkPkgNetAuth" Style="{StaticResource ToggleSwitchStyle}" Grid.Row="4" Content="Network login:" VerticalAlignment="Center"
                                              ToolTip="Tick only if the network folder needs a username and password."/>
                                    <StackPanel Grid.Row="4" Grid.Column="1" Grid.ColumnSpan="2" Orientation="Horizontal">
                                        <TextBlock Text="User" VerticalAlignment="Center" Margin="0,0,5,0"/>
                                        <TextBox x:Name="TxtNetUser" Width="150" IsEnabled="False" ToolTip="Type the USERNAME for the network share (e.g. DOMAIN\\user). Enabled only when 'Network login' is ticked."/>
                                        <TextBlock Text="Password" VerticalAlignment="Center" Margin="12,0,5,0"/>
                                        <PasswordBox x:Name="PwdNetPass" Width="150" IsEnabled="False" ToolTip="Type the PASSWORD for the network share. Enabled only when 'Network login' is ticked."/>
                                        <Button x:Name="BtnPkgNetTest" Content="Test login" IsEnabled="False" Margin="12,0,0,0"
                                                Style="{StaticResource SecondaryButtonStyle}"
                                                ToolTip="Check whether this username/password can connect to the network folder above."/>
                                    </StackPanel>

                                    <TextBlock Grid.Row="1" Text="Remote Directory:"/>
                                    <TextBox
                                        x:Name="TxtRemoteDirectory"
                                        Grid.Row="1"
                                        Grid.Column="1"
                                        Grid.ColumnSpan="2"
                                        ToolTip="Remote Linux directory used for package upload"/>

                                    <TextBlock Grid.Row="2" Text="Installation Mode:"/>
                                    <ComboBox
                                        x:Name="CmbInstallMode"
                                        Grid.Row="2"
                                        Grid.Column="1"
                                        Grid.ColumnSpan="2">
                                        <ComboBoxItem Content="Upgrade" IsSelected="True"/>
                                        <ComboBoxItem Content="Install"/>
                                    </ComboBox>

                                    <TextBlock Grid.Row="3" Text="Install Reason:"/>
                                    <TextBox
                                        x:Name="TxtInstallReason"
                                        Grid.Row="3"
                                        Grid.Column="1"
                                        Grid.ColumnSpan="2"
                                        ToolTip="Reason supplied to the package's install script (required for gaming-compliance packages). Sent both as the prompt answer and as the REASON environment variable."/>
                                </Grid>
                            </GroupBox>

                            <StackPanel Grid.Row="1" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="4,10,4,4">
                                <TextBlock Text="Deployment plan (each role-marked, connected server -> matched package):"
                                           Style="{StaticResource TargetLabelStyle}" VerticalAlignment="Center"/>
                                <Button x:Name="BtnBuildPlan" Content="Build / Refresh Plan" Style="{StaticResource PrimaryButtonStyle}"/>
                                <Button x:Name="BtnRemovePlanRow" Content="Remove Selected" Style="{StaticResource SecondaryButtonStyle}"/>
                                <Button x:Name="BtnClearPlan" Content="Clear Plan" Style="{StaticResource DangerButtonStyle}"/>
                            </StackPanel>

                            <DataGrid
                                x:Name="PackageGrid"
                                Grid.Row="2"
                                Grid.ColumnSpan="2"
                                AutoGenerateColumns="False"
                                CanUserAddRows="False"
                                CanUserDeleteRows="False"
                                SelectionMode="Extended"
                                SelectionUnit="FullRow"
                                HeadersVisibility="Column"
                                GridLinesVisibility="Horizontal"
                                Background="White"
                                RowBackground="White"
                                AlternatingRowBackground="#F8FAFC"
                                BorderBrush="{StaticResource BorderBrush}"
                                BorderThickness="1"
                                FontWeight="Normal">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Server IP / Host" Binding="{Binding Host}" Width="1.6*" IsReadOnly="True"/>
                                    <DataGridTextColumn Header="Role" Binding="{Binding Role}" Width="*" IsReadOnly="True"/>
                                    <DataGridTemplateColumn Header="Package (pick or skip)" Width="3.4*">
                                        <DataGridTemplateColumn.CellTemplate>
                                            <DataTemplate>
                                                <ComboBox Tag="PlanPackage" ItemsSource="{Binding Available}" SelectedItem="{Binding Package, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Margin="2"/>
                                            </DataTemplate>
                                        </DataGridTemplateColumn.CellTemplate>
                                    </DataGridTemplateColumn>
                                    <DataGridTextColumn Header="Size" Binding="{Binding Size}" Width="0.8*" IsReadOnly="True"/>
                                    <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="1.6*" IsReadOnly="True"/>
                                </DataGrid.Columns>
                            </DataGrid>

                            <StackPanel Grid.Row="3" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                                <TextBlock Text="SSL after install (Concentrator / Report Server / Appserver):" Style="{StaticResource TargetLabelStyle}" VerticalAlignment="Center"/>
                                <ComboBox x:Name="CmbSslAfterInstall" Width="120" Margin="0,0,12,0"
                                          ToolTip="After a successful install, optionally enable/disable SSL for Concentrator and Report Server (via nmenu) and OneLink Appserver (via app.properties). Appserver Enable needs a keystore at /opt/onelink/etc/client.ks - deploy one first on the Certificates tab. Restart the affected service afterwards to apply.">
                                    <ComboBoxItem Content="No change" IsSelected="True"/>
                                    <ComboBoxItem Content="Enable"/>
                                    <ComboBoxItem Content="Disable"/>
                                </ComboBox>
                                <CheckBox x:Name="ChkEnableStart" Style="{StaticResource ToggleSwitchStyle}" Content="Enable &amp; start service after install" VerticalAlignment="Center" Margin="0,0,12,0"
                                          ToolTip="If checked, after a successful install the service is enabled and started (systemctl enable --now). If unchecked, the package is only installed."/>
                                <Button
                                    x:Name="BtnUploadPackage"
                                    Content="Upload Only"
                                    Style="{StaticResource SecondaryButtonStyle}"/>
                                <Button
                                    x:Name="BtnUploadInstall"
                                    Content="Upload and Install"
                                    Style="{StaticResource SuccessButtonStyle}"/>
                            </StackPanel>

                            <!-- Service Installer: check status first, then start/restart/stop -->
                            <GroupBox Grid.Row="0" Grid.Column="0" Header="Service Installer (check status, then start / restart / stop)" Margin="0,0,10,10">
                              <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="12,8,12,0">
                                    <TextBlock Text="Target server:" Style="{StaticResource TargetLabelStyle}"/>
                                    <ToggleButton x:Name="BtnTargetService" MinWidth="200" MaxWidth="340" Content="All servers" Style="{StaticResource TargetPickerStyle}"
                                                  ToolTip="Pick one or more servers to act on"/>
                                    <Popup x:Name="PopTargetService" StaysOpen="False" Placement="Bottom" PlacementTarget="{Binding ElementName=BtnTargetService}" IsOpen="{Binding IsChecked, ElementName=BtnTargetService, Mode=TwoWay}">
                                        <Border Background="White" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,2,0,0">
                                            <ScrollViewer MaxHeight="240" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="PnlTargetService" MinWidth="200"/></ScrollViewer>
                                        </Border>
                                    </Popup>
                                    <Button x:Name="BtnRefreshServices" Content="Refresh" Style="{StaticResource SecondaryButtonStyle}" MinWidth="80"/>
                                </StackPanel>
                                <Grid Margin="12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="135"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>

                                    <TextBlock Grid.Row="0" Text="Services:" VerticalAlignment="Top" Margin="0,6,0,0"/>
                                    <StackPanel Grid.Row="0" Grid.Column="1" Margin="5" HorizontalAlignment="Left" Width="430">
                                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                                            <TextBlock Text="Find:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                                            <TextBox x:Name="TxtServiceSearch" Width="150" VerticalAlignment="Center"
                                                     ToolTip="Type to filter the service list by name"/>
                                            <Button x:Name="BtnSvcSelectAll" Content="Select all" Style="{StaticResource SecondaryButtonStyle}" MinWidth="80"
                                                    ToolTip="Tick all services currently shown"/>
                                            <Button x:Name="BtnSvcDeselectAll" Content="Deselect all" Style="{StaticResource SecondaryButtonStyle}" MinWidth="80"
                                                    ToolTip="Untick all services currently shown"/>
                                        </StackPanel>
                                        <Border BorderBrush="{StaticResource BorderBrush}" BorderThickness="1"
                                                CornerRadius="4" Background="White" MinHeight="90">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="150">
                                                <StackPanel x:Name="SvcCheckPanel" Margin="8"/>
                                            </ScrollViewer>
                                        </Border>
                                    </StackPanel>

                                    <TextBlock Grid.Row="1" Text="Action:"/>
                                    <ComboBox x:Name="CmbServiceAction" Grid.Row="1" Grid.Column="1" Width="200" HorizontalAlignment="Left">
                                        <ComboBoxItem Content="Restart" IsSelected="True"/>
                                        <ComboBoxItem Content="Stop"/>
                                    </ComboBox>

                                    <StackPanel Grid.Row="2" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                                        <Button x:Name="BtnServiceStatus" Content="Check Service Status" Style="{StaticResource SecondaryButtonStyle}"/>
                                        <Button x:Name="BtnServiceDetails" Content="Check Details (version)" Style="{StaticResource SecondaryButtonStyle}"
                                                ToolTip="Show the installed package name/version and status for the selected service"/>
                                    </StackPanel>
                                    <Button x:Name="BtnServiceAction" Grid.Row="3" Grid.ColumnSpan="2"
                                            Content="Start / Restart / Stop Service" Style="{StaticResource PrimaryButtonStyle}"
                                            HorizontalAlignment="Right" Margin="0,4,0,0"/>
                                </Grid>
                              </StackPanel>
                            </GroupBox>
                        </Grid>
                    </ScrollViewer>
                </TabItem>

                <!-- Certificates tab - deploy a certificate file to the server(s) -->
                <TabItem x:Name="TabMetrics" Header="Metrics">
                    <Grid Margin="12">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="2,0,2,6">
                            <TextBlock Text="Activity Metrics" FontSize="14" FontWeight="Bold" Foreground="{StaticResource PrimaryDarkBrush}" VerticalAlignment="Center" Margin="0,0,14,0"/>
                            <CheckBox x:Name="ChkCaptureMetrics" Style="{StaticResource ToggleSwitchStyle}" Content="Record efficiency metrics" VerticalAlignment="Center" Margin="0,0,14,0"
                                      ToolTip="When ON, each completed activity records its clicks, distinct fields edited and elapsed time. When OFF, nothing is captured."/>
                            <Button x:Name="BtnExportMetrics" Content="Export CSV" Style="{StaticResource SecondaryButtonStyle}"/>
                            <Button x:Name="BtnClearMetrics" Content="Clear" Style="{StaticResource DangerButtonStyle}"/>
                        </StackPanel>

                        <Border Grid.Row="1" Background="#EEF2F7" CornerRadius="6" Padding="10,6" Margin="2,0,2,6">
                            <TextBlock x:Name="TxtActivitySummary" Text="No activities recorded yet." FontWeight="SemiBold" Foreground="{StaticResource PrimaryDarkBrush}" TextWrapping="Wrap"/>
                        </Border>

                        <DataGrid x:Name="ActivityGrid" Grid.Row="2"
                                  AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False"
                                  IsReadOnly="True" HeadersVisibility="Column" GridLinesVisibility="Horizontal"
                                  Background="White" RowBackground="White" AlternatingRowBackground="#F8FAFC"
                                  BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" FontWeight="Normal">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Time started" Binding="{Binding Time}" Width="1*"/>
                                <DataGridTextColumn Header="Activity" Binding="{Binding Activity}" Width="2*"/>
                                <DataGridTextColumn Header="Target server" Binding="{Binding Target}" Width="1.5*"/>
                                <DataGridTextColumn Header="Mouse clicks" Binding="{Binding Clicks}" Width="1*"/>
                                <DataGridTextColumn Header="Fields edited" Binding="{Binding Inputs}" Width="1*"/>
                                <DataGridTextColumn Header="Active time (s)" Binding="{Binding ActivitySeconds}" Width="1.3*"/>
                                <DataGridTextColumn Header="Server op (s)" Binding="{Binding OperationSeconds}" Width="1.2*"/>
                                <DataGridTextColumn Header="Outcome" Binding="{Binding Outcome}" Width="1*"/>
                            </DataGrid.Columns>
                        </DataGrid>
                    </Grid>
                </TabItem>
            </TabControl>
        </Grid>

        <!-- Activity log -->
        <GroupBox
            Grid.Row="2"
            Header="Activity Log"
            Height="450"
            Margin="18,8,18,14">

            <Grid Margin="8">

                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBox
                    x:Name="TxtLog"
                    Grid.Row="0"
                    MinHeight="330"
                    VerticalContentAlignment="Top"
                    IsReadOnly="True"
                    AcceptsReturn="True"
                    VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Auto"
                    FontFamily="Consolas"
                    FontSize="12"
                    TextWrapping="NoWrap"
                    Background="#111827"
                    Foreground="#D1FAE5"
                    BorderThickness="0"/>

                <StackPanel
                    Grid.Row="1"
                    Orientation="Horizontal"
                    HorizontalAlignment="Right">

                    <Button
                        x:Name="BtnClearLog"
                        Content="Clear Log"
                        Style="{StaticResource SecondaryButtonStyle}"/>

                    <Button
                        x:Name="BtnOpenLog"
                        Content="Open Log File"
                        Style="{StaticResource PrimaryButtonStyle}"/>
                </StackPanel>
            </Grid>
        </GroupBox>
        </Grid>
        </ScrollViewer>

				<!-- Footer -->
		<Border
			Grid.Row="2"
			Background="#1E293B"
			BorderThickness="0,1,0,0"
			BorderBrush="#CBD5E1">

			<Grid Margin="12,0">

				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
					<ColumnDefinition Width="Auto"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>

				<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
					<TextBlock
						VerticalAlignment="Center"
						Foreground="White"
						FontSize="12"
						FontWeight="SemiBold"
						x:Name="TxtAppFooter" Text="Foreman &#183; Aristocrat Customer Success"/>
					<Button x:Name="BtnUnlockMetrics" Content="Efficiency Recorder" Style="{StaticResource FooterButtonStyle}" Margin="16,0,0,0"
						ToolTip="Open the Efficiency Recorder (capture and report usage metrics)"/>
					<Button x:Name="BtnLogFolder" Content="Change Log Folder" Style="{StaticResource FooterButtonStyle}"
						ToolTip="Choose where log files are saved. Foreman remembers this the next time you open it."/>
					<Button x:Name="BtnResetTool" Content="Reset Tool" Style="{StaticResource FooterButtonStyle}"
						ToolTip="If Foreman has been left open a long time and starts acting up (stuck buttons, a connection that never responds), click this. It clears stuck internal state and every server connection - WITHOUT closing Foreman or losing your server list, settings, or package plan. Click Connect All afterwards."/>
				</StackPanel>

				<TextBlock
					Grid.Column="1"
					Margin="30,0"
					VerticalAlignment="Center"
					Foreground="#E2E8F0"
					FontSize="12"
					Text="Version : 1.1.0"/>

				<TextBlock
					Grid.Column="2"
					Margin="30,0"
					VerticalAlignment="Center"
					Foreground="#E2E8F0"
					FontSize="12"
					Text="Latest Update : 02-Sep-2026"/>

				<TextBlock
					x:Name="TxtActivityHud"
					Grid.Column="3"
					Margin="30,0"
					VerticalAlignment="Center"
					Foreground="#22C55E"
					FontWeight="Bold"
					FontSize="12"
					Text="Ready"/>

			</Grid>

		</Border>
    </Grid>
</Window>
'@

