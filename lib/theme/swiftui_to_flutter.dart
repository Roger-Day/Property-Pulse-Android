// ─────────────────────────────────────────────────────────────────────────────
// SWIFTUI → FLUTTER/M3 TRANSLATION REFERENCE
// This file documents the canonical mapping used across all Property Pulse
// screens. Every developer on this project must follow these equivalences.
// ─────────────────────────────────────────────────────────────────────────────
//
// NAVIGATION
//   NavigationStack          → GoRouter (root) / Navigator.push (modal)
//   NavigationLink           → context.push('/route') / context.go('/route')
//   .navigationTitle()       → AppBar(title: Text(...))
//   .navigationBarTitleDisplayMode(.large) → SliverAppBar with large title
//   .navigationBarTitleDisplayMode(.inline) → AppBar (standard height)
//   .toolbar { ... }         → AppBar.actions: [...]
//   .toolbarBackground()     → AppBar(backgroundColor:)
//   dismiss()                → context.pop() / Navigator.of(context).pop()
//   path.append(item)        → context.push('/route')
//   path.removeAll()         → context.go('/root-route')
//
// MODAL PRESENTATIONS
//   .sheet(isPresented:)     → showModalBottomSheet(isScrollControlled: true)
//   .fullScreenCover         → Navigator.push(MaterialPageRoute(fullscreenDialog: true))
//   .confirmationDialog()    → showModalBottomSheet with list of actions
//   .alert()                 → showDialog(builder: (_) => AlertDialog(...))
//   .popover()               → showMenu() / PopupMenuButton
//   .contextMenu()           → GestureDetector(onLongPress) + showMenu()
//
// LAYOUT
//   VStack                   → Column
//   HStack                   → Row
//   ZStack                   → Stack
//   LazyVStack               → ListView.builder / SliverList
//   LazyHStack               → ListView (horizontal) / SliverList
//   LazyVGrid                → GridView.builder
//   LazyHGrid                → GridView (horizontal)
//   ScrollView               → SingleChildScrollView / CustomScrollView
//   GeometryReader           → LayoutBuilder / MediaQuery
//   Spacer()                 → Spacer() / SizedBox.expand()
//   Divider()                → Divider(height: 1)
//   Group { }                → Fragment (no widget equiv — use Column/Row)
//
// CONTROLS
//   Text("...")              → Text("...")
//   TextField                → TextField / TextFormField
//   SecureField              → TextField(obscureText: true)
//   Toggle                   → Switch / SwitchListTile
//   Slider                   → Slider
//   Stepper                  → Row with +/- IconButtons (custom _StepCounter)
//   Picker (segmented)       → SegmentedButton<T>
//   Picker (menu)            → DropdownButtonFormField / showModalBottomSheet
//   DatePicker               → showDatePicker() / showTimePicker()
//   Button                   → ElevatedButton / FilledButton / TextButton
//   Link                     → GestureDetector + launchUrl()
//   Image(systemName:)       → Icon(Icons.xxx)
//   AsyncImage               → CachedNetworkImage
//   ProgressView()           → CircularProgressIndicator
//   ProgressView(value:)     → LinearProgressIndicator
//   List                     → ListView / ListView.separated
//   ForEach in List          → ListView.builder(itemBuilder:)
//   Section(header:)         → Sticky header via SliverPersistentHeader
//   Form { Section {} }      → Column with _FormSection cards
//   NavigationView (split)   → adaptive split view (tablet only)
//
// STATES & INTERACTION
//   @State var x = y        → StatefulWidget + setState(() => x = y)
//   .onAppear {}             → initState() / didChangeDependencies()
//   .onDisappear {}          → dispose()
//   .onChange(of: x) {}     → ValueListenableBuilder / StreamBuilder
//   .task {}                 → FutureBuilder / initState + Future
//   .refreshable {}          → RefreshIndicator
//   .searchable()            → SearchBar / TextField in AppBar
//   .swipeActions()          → Dismissible widget
//   .contextMenu()           → long-press + showMenu()
//
// STYLING
//   .foregroundColor()       → style: TextStyle(color:) / IconTheme
//   .background()            → decoration: BoxDecoration(color:)
//   .cornerRadius()          → BorderRadius.circular(r) in BoxDecoration
//   .padding()               → Padding(padding: EdgeInsets...)
//   .frame(width:height:)    → SizedBox(width:, height:)
//   .frame(maxWidth:.infinity) → SizedBox.expand() / double.infinity
//   .shadow()                → BoxShadow in BoxDecoration
//   .opacity()               → Opacity(opacity:) / withOpacity()
//   .overlay()               → Stack with Positioned.fill
//   .clipShape(Circle())     → ClipOval / shape: CircleBorder
//   .clipShape(RoundedRectangle(cornerRadius: r)) → ClipRRect(borderRadius:)
//   .scaleEffect()           → Transform.scale()
//   .rotationEffect()        → Transform.rotate()
//   .offset()                → Transform.translate() / Positioned
//   .blur()                  → ImageFilter.blur via BackdropFilter
//   .tint()                  → Color / iconColor
//   .font(.headline)         → style: PPTypography.headline
//   .font(.caption)          → style: PPTypography.caption1
//   .fontWeight(.bold)       → fontWeight: FontWeight.w700
//   .lineLimit(n)            → maxLines: n, overflow: TextOverflow.ellipsis
//   .multilineTextAlignment  → textAlign: TextAlign.center/left/right
//   .hoverEffect()           → InkWell / InkResponse
//
// ANIMATION
//   withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {}
//     → AnimatedContainer(duration: PPAnimations.standard, curve: PPAnimations.springUI)
//   .animation(.easeInOut(duration: 0.2), value: x)
//     → AnimatedContainer / AnimatedOpacity / TweenAnimationBuilder
//   .transition(.opacity)    → FadeTransition
//   .transition(.scale)      → ScaleTransition
//   .transition(.move(edge: .bottom)) → SlideTransition
//   .matchedGeometryEffect() → Hero widget
//   .spring()                → Curves.elasticOut / SpringDescription
//
// PROPERTY PULSE-SPECIFIC MAPPINGS (design tokens → widgets)
//   AppColors.primary        → PPColors.primaryLight (light) / Theme.of(ctx).colorScheme.primary
//   AppSpacing.md (16)       → const EdgeInsets.all(PPSpacing.md)
//   AppCornerRadius.medium(12) → BorderRadius.circular(PPRadius.md)
//   AppShadow.small          → PPShadows.small (BoxShadow list)
//   AppTouchTargets.standard(48) → minimumSize: Size.fromHeight(PPTouchTargets.standard)
//   PrimaryButton(title)     → FilledButton(child: Text(title))
//   SecondaryButton(title)   → OutlinedButton(child: Text(title))
//   CardView { }             → Card or Container with PPShadows.card
//   SectionHeader(title:)    → _SectionHeader widget (home_screen.dart pattern)
//   EmptyStateView(icon:title:message:) → EmptyState widget (see below)
//   SkeletonView()           → Shimmer.fromColors(child: ...)
//   HapticFeedback.medium()  → HapticFeedback.mediumImpact()
//   HapticFeedback.light()   → HapticFeedback.lightImpact()
//   HapticFeedback.success() → HapticFeedback.vibrate()

// ignore_for_file: unused_import
// This file is documentation only — it is never imported at runtime.
