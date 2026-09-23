//
//  MainWindowController.m
//  DiskArbitrator
//
//  Programmatic rebuild of the main window to match the OpenDesign prototype.
//

#import "MainWindowController.h"
#import "DiskArbitratorAppController.h"
#import "Arbitrator.h"
#import "Disk.h"
#import "DiskCell.h"
#import <DiskArbitration/DiskArbitration.h>

static void * const kDisksObservingContext = (void *)&kDisksObservingContext;

static NSString * const kDeviceColumnIdentifier    = @"Device";
static NSString * const kBSDNameColumnIdentifier    = @"BSDName";
static NSString * const kMountStateColumnIdentifier = @"MountState";
static NSString * const kFilesystemColumnIdentifier = @"Filesystem";
static NSString * const kCapacityColumnIdentifier   = @"Capacity";
static NSString * const kProtocolColumnIdentifier   = @"Protocol";

////////////////////////////////////////////////////////////////////////////////

#pragma mark - Disk UI helpers

@implementation Disk (DiskArbitratorUI)

- (NSString *)uiVolumeKind
{
	NSString *kind = self.diskDescription[(NSString *)kDADiskDescriptionVolumeKindKey];
	if (!kind) return NSLocalizedString(@"—", nil);
	if ([kind isEqual:@"apfs"])            return @"APFS";
	if ([kind isEqual:@"hfs"])             return @"HFS+";
	if ([kind isEqual:@"exfat"])           return @"exFAT";
	if ([kind isEqual:@"msdos"])           return @"MS-DOS (FAT)";
	if ([kind isEqual:@"ntfs"])            return @"NTFS";
	if ([kind isEqual:@"nfs"])             return @"NFS";
	if ([kind isEqual:@"udf"])             return @"UDF";
	return [kind capitalizedString];
}

- (NSString *)uiProtocol
{
	NSString *protocol = self.diskDescription[(NSString *)kDADiskDescriptionDeviceProtocolKey];
	return protocol ?: NSLocalizedString(@"Internal", nil);
}

- (NSString *)uiCapacity
{
	NSNumber *size = self.diskDescription[(NSString *)kDADiskDescriptionMediaSizeKey];
	if (!size) return NSLocalizedString(@"—", nil);
	double bytes = [size doubleValue];
	double base = 1000.0;
	if (bytes >= pow(base, 4)) return [NSString stringWithFormat:@"%.2f TB", bytes / pow(base, 4)];
	if (bytes >= pow(base, 3)) return [NSString stringWithFormat:@"%.2f GB", bytes / pow(base, 3)];
	if (bytes >= pow(base, 2)) return [NSString stringWithFormat:@"%.2f MB", bytes / pow(base, 2)];
	if (bytes >= base)          return [NSString stringWithFormat:@"%.2f KB", bytes / base];
	return [NSString stringWithFormat:@"%.0f B", bytes];
}

- (NSString *)uiMountState
{
	if (self.rejectedMount)                 return NSLocalizedString(@"Blocked by Policy", nil);
	if (!self.isMounted && self.isMountable) return NSLocalizedString(@"Not Mounted", nil);
	if (self.isMounted) {
		if (self.isFileSystemWritable) return NSLocalizedString(@"Mounted Read-Write", nil);
		return NSLocalizedString(@"Mounted Read-Only", nil);
	}
	if (self.isWholeDisk) return NSLocalizedString(@"Media", nil);
	return NSLocalizedString(@"Not Mounted", nil);
}

- (NSString *)uiMediaName
{
	return self.diskDescription[(NSString *)kDADiskDescriptionMediaNameKey];
}

- (NSString *)uiMediaKind
{
	return self.diskDescription[(NSString *)kDADiskDescriptionMediaKindKey];
}

- (NSString *)uiBlockSize
{
	NSNumber *blockSize = self.diskDescription[(NSString *)kDADiskDescriptionMediaBlockSizeKey];
	return blockSize ? [NSString stringWithFormat:@"%@ bytes", blockSize] : NSLocalizedString(@"—", nil);
}

- (NSString *)uiVendor
{
	return self.diskDescription[(NSString *)kDADiskDescriptionDeviceVendorKey] ?: NSLocalizedString(@"—", nil);
}

- (NSString *)uiModel
{
	return self.diskDescription[(NSString *)kDADiskDescriptionDeviceModelKey] ?: NSLocalizedString(@"—", nil);
}

- (NSString *)uiMountPath
{
	NSURL *url = self.diskDescription[(NSString *)kDADiskDescriptionVolumePathKey];
	return url ? [url path] : NSLocalizedString(@"Not Mounted", nil);
}

- (BOOL)isDiskImage
{
	NSString *protocol = [self uiProtocol];
	NSString *mediaName = self.uiMediaName;
	if ([protocol containsString:@"Virtual"]) return YES;
	if (mediaName && [mediaName.lowercaseString hasSuffix:@".dmg"]) return YES;
	return NO;
}

@end

////////////////////////////////////////////////////////////////////////////////

@interface MainWindowController ()
- (void)setModeFromControl:(NSSegmentedControl *)sender;
- (void)applyFilterAtIndex:(NSUInteger)index;
- (void)updateInspectorForSelectedDisk:(Disk *)disk;
@end

@implementation MainWindowController

- (instancetype)initWithAppController:(AppController *)appController arbitrator:(Arbitrator *)arbitrator
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1220, 720)
												  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
															 NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
													backing:NSBackingStoreBuffered
													  defer:NO];
	window.title = NSLocalizedString(@"Disk Arbitrator", nil);
	window.minSize = NSMakeSize(900, 560);
	[window center];

	self = [super initWithWindow:window];
	if (self) {
		_appController = appController;
		_arbitrator = arbitrator;
		[self buildWindowContent];
		[self setupArrayController];
		[self setupTableBindings];
		[self.arbitrator addObserver:self forKeyPath:@"disks" options:0 context:kDisksObservingContext];
		[self refreshDisplays];
	}
	return self;
}

- (void)dealloc
{
	if (self.arbitrator)
		[self.arbitrator removeObserver:self forKeyPath:@"disks" context:kDisksObservingContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == kDisksObservingContext)
		[self refreshDisplays];
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Content building

- (void)buildWindowContent
{
	NSView *contentView = self.window.contentView;

	NSView *modeBar = [self buildModeBar];
	NSSplitView *split = [self buildMainSplit];

	[contentView addSubview:modeBar];
	[contentView addSubview:split];

	[NSLayoutConstraint activateConstraints:@[
		[modeBar.topAnchor constraintEqualToAnchor:contentView.topAnchor],
		[modeBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
		[modeBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
		[modeBar.heightAnchor constraintEqualToConstant:64],
		[split.topAnchor constraintEqualToAnchor:modeBar.bottomAnchor],
		[split.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
		[split.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
		[split.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
	]];

	[self.window setFrameAutosaveName:@"DiskArbitratorMainWindow"];
}

#pragma mark Mode bar

- (NSView *)buildModeBar
{
	NSView *bar = [[NSView alloc] initWithFrame:NSZeroRect];
	bar.translatesAutoresizingMaskIntoConstraints = NO;

	self.modeHeadlineLabel = [NSTextField labelWithString:NSLocalizedString(@"Block Mounts Mode Active", nil)];
	self.modeHeadlineLabel.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
	self.modeHeadlineLabel.translatesAutoresizingMaskIntoConstraints = NO;

	self.modeDescriptionLabel = [NSTextField labelWithString:
		NSLocalizedString(@"System rejects all automatic mount requests. Attached disks remain unmounted.", nil)];
	self.modeDescriptionLabel.textColor = NSColor.secondaryLabelColor;
	self.modeDescriptionLabel.font = [NSFont systemFontOfSize:11];
	self.modeDescriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;

	self.modeSegmentControl = [NSSegmentedControl segmentedControlWithLabels:
		@[ NSLocalizedString(@"Block Mounts", nil),
		   NSLocalizedString(@"Read-Only", nil),
		   NSLocalizedString(@"Deactivated", nil) ]
		trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(setModeFromControl:)];
	self.modeSegmentControl.selectedSegment = 0;
	self.modeSegmentControl.translatesAutoresizingMaskIntoConstraints = NO;

	[bar addSubview:self.modeHeadlineLabel];
	[bar addSubview:self.modeDescriptionLabel];
	[bar addSubview:self.modeSegmentControl];

	[NSLayoutConstraint activateConstraints:@[
		[self.modeHeadlineLabel.topAnchor constraintEqualToAnchor:bar.topAnchor constant:8],
		[self.modeHeadlineLabel.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:16],
		[self.modeDescriptionLabel.topAnchor constraintEqualToAnchor:self.modeHeadlineLabel.bottomAnchor constant:4],
		[self.modeDescriptionLabel.leadingAnchor constraintEqualToAnchor:self.modeHeadlineLabel.leadingAnchor],
		[self.modeSegmentControl.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-16],
		[self.modeSegmentControl.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
	]];
	return bar;
}

- (void)setModeFromControl:(NSSegmentedControl *)sender
{
	switch (sender.selectedSegment) {
		case 0:
			[self.appController performActivation:nil];
			[self.appController performSetMountBlockMode:nil];
			break;
		case 1:
			[self.appController performActivation:nil];
			[self.appController performSetMountReadOnlyMode:nil];
			break;
		default:
			[self.appController performDeactivation:nil];
			break;
	}
	[self refreshDisplays];
}

#pragma mark Main split (sidebar | content)

- (NSSplitView *)buildMainSplit
{
	NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	split.vertical = YES;
	split.dividerStyle = NSSplitViewDividerStyleThin;
	split.translatesAutoresizingMaskIntoConstraints = NO;

	NSView *sidebar = [self buildSidebar];
	NSView *content = [self buildContentPane];

	[split addArrangedSubview:sidebar];
	[split addArrangedSubview:content];
	[sidebar.widthAnchor constraintEqualToConstant:220].active = YES;
	[split setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:0];
	return split;
}

#pragma mark Sidebar

- (NSView *)buildSidebar
{
	NSView *sidebar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
	sidebar.translatesAutoresizingMaskIntoConstraints = NO;

	self.badgeAllCount = [self badgeLabel];
	self.badgeExternalCount = [self badgeLabel];
	self.badgeImagesCount = [self badgeLabel];
	self.badgeRejectionsCount = [self badgeLabel];

	NSView *spacer = [NSView new];
	spacer.translatesAutoresizingMaskIntoConstraints = NO;
	[spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
	[spacer setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

	NSStackView *stack = [NSStackView stackViewWithViews:@[
		[self sidebarSection:@"Devices"],
		[self sidebarItem:@"All Storage" badge:self.badgeAllCount tag:0],
		[self sidebarItem:@"External Media" badge:self.badgeExternalCount tag:1],
		[self sidebarItem:@"Disk Images" badge:self.badgeImagesCount tag:2],
		[self sidebarSection:@"Forensics"],
		[self sidebarItem:@"Rejection Audits" badge:self.badgeRejectionsCount tag:3],
		[self sidebarItem:@"Integrity Guard" badge:nil tag:4],
		spacer,
		[self buildLaunchAgentCard],
	]];
	stack.orientation = NSUserInterfaceLayoutOrientationVertical;
	stack.alignment = NSLayoutAttributeLeading;
	stack.spacing = 2;
	stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
	stack.translatesAutoresizingMaskIntoConstraints = NO;

	[sidebar addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor],
	]];
	return sidebar;
}

- (NSTextField *)sidebarSection:(NSString *)title
{
	NSTextField *label = [NSTextField labelWithString:title.uppercaseString];
	label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
	label.textColor = NSColor.secondaryLabelColor;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	return label;
}

- (NSView *)sidebarItem:(NSString *)title badge:(NSTextField *)badge tag:(NSInteger)tag
{
	NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(sidebarItemClicked:)];
	button.bezelStyle = NSBezelStyleInline; // minimal
	button.tag = tag;
	button.translatesAutoresizingMaskIntoConstraints = NO;

	if (badge) {
		NSStackView *row = [NSStackView stackViewWithViews:@[ button, badge ]];
		row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
		row.spacing = 8;
		row.alignment = NSLayoutAttributeCenterY;
		row.translatesAutoresizingMaskIntoConstraints = NO;
		[badge.widthAnchor constraintEqualToConstant:24].active = YES;
		return row;
	}
	return button;
}

- (NSTextField *)badgeLabel
{
	NSTextField *badge = [NSTextField labelWithString:@"0"];
	badge.alignment = NSTextAlignmentCenter;
	badge.font = [NSFont systemFontOfSize:10];
	badge.textColor = NSColor.tertiaryLabelColor;
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	return badge;
}

- (NSView *)buildLaunchAgentCard
{
	NSView *card = [[NSView alloc] initWithFrame:NSZeroRect];
	card.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *title = [NSTextField labelWithString:NSLocalizedString(@"Launch Agent", nil)];
	title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
	title.translatesAutoresizingMaskIntoConstraints = NO;

	self.launchAgentStatusLabel = [NSTextField labelWithString:NSLocalizedString(@"Active", nil)];
	self.launchAgentStatusLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
	self.launchAgentStatusLabel.textColor = NSColor.systemGreenColor;
	self.launchAgentStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *desc = [NSTextField wrappingLabelWithString:
		NSLocalizedString(@"launchd watchdog monitors the process.", nil)];
	desc.font = [NSFont systemFontOfSize:10];
	desc.textColor = NSColor.secondaryLabelColor;
	desc.translatesAutoresizingMaskIntoConstraints = NO;

	[card addSubview:title];
	[card addSubview:self.launchAgentStatusLabel];
	[card addSubview:desc];

	[NSLayoutConstraint activateConstraints:@[
		[title.topAnchor constraintEqualToAnchor:card.topAnchor],
		[title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
		[self.launchAgentStatusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
		[self.launchAgentStatusLabel.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
		[desc.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
		[desc.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
		[desc.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
		[desc.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
	]];
	return card;
}

- (void)sidebarItemClicked:(NSButton *)sender
{
	[self applyFilterAtIndex:sender.tag];
}

- (void)applyFilterAtIndex:(NSUInteger)index
{
	NSPredicate *predicate = nil;
	switch (index) {
		case 0: predicate = nil; break;
		case 1: predicate = [NSPredicate predicateWithFormat:@"isRemovable == YES"]; break;
		case 2: predicate = [NSPredicate predicateWithFormat:@"isDiskImage == YES"]; break;
		case 3: // Rejection Audits - show disks blocked by policy
			predicate = [NSPredicate predicateWithFormat:@"rejectedMount == YES"]; break;
		default: break;
	}
	self.disksArrayController.filterPredicate = predicate;
	[self.tableView reloadData];
	[self refreshDisplays];
}

#pragma mark Content pane

- (NSView *)buildContentPane
{
	NSStackView *content = [NSStackView stackViewWithViews:@[
		[self buildTelemetryStrip],
		[self buildTableInspectorSplit],
	]];
	content.orientation = NSUserInterfaceLayoutOrientationVertical;
	content.spacing = 8;
	content.edgeInsets = NSEdgeInsetsMake(8, 12, 8, 12);
	content.distribution = NSStackViewDistributionFill;
	content.translatesAutoresizingMaskIntoConstraints = NO;
	return content;
}

- (NSView *)buildTelemetryStrip
{
	NSStackView *strip = [NSStackView stackViewWithViews:@[
		[self telemetryCard:NSLocalizedString(@"Arbitration Status", nil) valueLabel:&_telemetryStatusValue],
		[self telemetryCard:NSLocalizedString(@"Write-Shield Ratio", nil) valueLabel:&_telemetryShieldValue],
		[self telemetryCard:NSLocalizedString(@"Active Block Devices", nil) valueLabel:&_telemetryDevicesValue],
	]];
	strip.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	strip.spacing = 8;
	strip.distribution = NSStackViewDistributionFillEqually;
	strip.translatesAutoresizingMaskIntoConstraints = NO;
	[strip.heightAnchor constraintEqualToConstant:72].active = YES;
	return strip;
}

- (NSView *)telemetryCard:(NSString *)title valueLabel:(NSTextField * __strong *)valueLabel
{
	NSView *card = [[NSView alloc] initWithFrame:NSZeroRect];
	card.wantsLayer = YES;
	card.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
	card.layer.cornerRadius = 8;
	card.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *titleLabel = [NSTextField labelWithString:title];
	titleLabel.font = [NSFont systemFontOfSize:11];
	titleLabel.textColor = NSColor.secondaryLabelColor;
	titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *value = [NSTextField labelWithString:@"—"];
	value.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
	value.translatesAutoresizingMaskIntoConstraints = NO;
	*valueLabel = value;

	[card addSubview:titleLabel];
	[card addSubview:value];
	[NSLayoutConstraint activateConstraints:@[
		[titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
		[titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
		[value.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
		[value.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8],
	]];
	return card;
}

- (NSView *)buildTableInspectorSplit
{
	NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	split.vertical = YES;
	split.dividerStyle = NSSplitViewDividerStyleThin;
	split.translatesAutoresizingMaskIntoConstraints = NO;

	NSView *tableContainer = [self buildTableContainer];
	NSView *inspector = [self buildInspector];

	[split addArrangedSubview:tableContainer];
	[split addArrangedSubview:inspector];
	[tableContainer.widthAnchor constraintGreaterThanOrEqualToConstant:640].active = YES;
	[inspector.widthAnchor constraintEqualToConstant:240].active = YES;
	[split setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
	[split setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:1];
	return split;
}

- (NSView *)buildTableContainer
{
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 720, 420)];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	scroll.hasVerticalScroller = YES;
	scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 720, 420)];
	table.rowHeight = 26;
	table.usesAlternatingRowBackgroundColors = YES;
	table.allowsEmptySelection = NO;
	table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
	table.translatesAutoresizingMaskIntoConstraints = NO;

	NSTableColumn *deviceColumn = [[NSTableColumn alloc] initWithIdentifier:kDeviceColumnIdentifier];
	deviceColumn.title = NSLocalizedString(@"Device", nil);
	deviceColumn.width = 170;
	deviceColumn.dataCell = [[DiskCell alloc] init];
	[table addTableColumn:deviceColumn];

	NSTableColumn *bsdColumn = [[NSTableColumn alloc] initWithIdentifier:kBSDNameColumnIdentifier];
	bsdColumn.title = NSLocalizedString(@"BSD Name", nil);
	bsdColumn.width = 70;
	[table addTableColumn:bsdColumn];

	NSTableColumn *mountColumn = [[NSTableColumn alloc] initWithIdentifier:kMountStateColumnIdentifier];
	mountColumn.title = NSLocalizedString(@"Mount State", nil);
	mountColumn.width = 120;
	[table addTableColumn:mountColumn];

	NSTableColumn *fsColumn = [[NSTableColumn alloc] initWithIdentifier:kFilesystemColumnIdentifier];
	fsColumn.title = NSLocalizedString(@"Filesystem", nil);
	fsColumn.width = 90;
	[table addTableColumn:fsColumn];

	NSTableColumn *capColumn = [[NSTableColumn alloc] initWithIdentifier:kCapacityColumnIdentifier];
	capColumn.title = NSLocalizedString(@"Capacity", nil);
	capColumn.width = 80;
	[table addTableColumn:capColumn];

	NSTableColumn *protoColumn = [[NSTableColumn alloc] initWithIdentifier:kProtocolColumnIdentifier];
	protoColumn.title = NSLocalizedString(@"Protocol", nil);
	protoColumn.width = 120;
	[table addTableColumn:protoColumn];

	table.dataSource = self.appController;
	table.delegate = self;
	self.tableView = table;

	scroll.documentView = table;
	return scroll;
}

- (NSView *)buildInspector
{
	NSView *inspector = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
	inspector.translatesAutoresizingMaskIntoConstraints = NO;

	self.inspectorTitleLabel = [NSTextField labelWithString:NSLocalizedString(@"Disk Inspector", nil)];
	self.inspectorTitleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
	self.inspectorTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView *rows = [NSStackView stackViewWithViews:@[
		[self inspectorRow:@"BSD Name" label:&_inspectorBSDName],
		[self inspectorRow:@"Mount Path" label:&_inspectorMountPath],
		[self inspectorRow:@"Media Kind" label:&_inspectorMediaKind],
		[self inspectorRow:@"Protocol" label:&_inspectorMediaProtocol],
		[self inspectorRow:@"Block Size" label:&_inspectorBlockSize],
		[self inspectorRow:@"Vendor" label:&_inspectorVendor],
		[self inspectorRow:@"Model" label:&_inspectorModel],
		[self inspectorRow:@"Removable" label:&_inspectorRemovable],
		[self inspectorRow:@"Ejectable" label:&_inspectorEjectable],
	]];
	rows.orientation = NSUserInterfaceLayoutOrientationVertical;
	rows.alignment = NSLayoutAttributeLeading;
	rows.spacing = 6;
	rows.translatesAutoresizingMaskIntoConstraints = NO;

	[inspector addSubview:self.inspectorTitleLabel];
	[inspector addSubview:rows];
	[NSLayoutConstraint activateConstraints:@[
		[self.inspectorTitleLabel.topAnchor constraintEqualToAnchor:inspector.topAnchor constant:12],
		[self.inspectorTitleLabel.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:12],
		[rows.topAnchor constraintEqualToAnchor:self.inspectorTitleLabel.bottomAnchor constant:12],
		[rows.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:12],
		[rows.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-12],
	]];
	return inspector;
}

- (NSView *)inspectorRow:(NSString *)title label:(NSTextField * __strong *)label
{
	NSTextField *keyLabel = [NSTextField labelWithString:title];
	keyLabel.font = [NSFont systemFontOfSize:11];
	keyLabel.textColor = NSColor.secondaryLabelColor;
	keyLabel.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *value = [NSTextField labelWithString:@"—"];
	value.font = [NSFont systemFontOfSize:11];
	value.lineBreakMode = NSLineBreakByTruncatingMiddle;
	value.translatesAutoresizingMaskIntoConstraints = NO;
	*label = value;

	NSStackView *row = [NSStackView stackViewWithViews:@[ keyLabel, value ]];
	row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	row.spacing = 10;
	row.alignment = NSLayoutAttributeFirstBaseline;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	[keyLabel.widthAnchor constraintEqualToConstant:90].active = YES;
	return row;
}

#pragma mark - Data

- (void)setupArrayController
{
	self.disksArrayController = [[NSArrayController alloc] init];
	self.disksArrayController.automaticallyPreparesContent = YES;
	self.disksArrayController.selectsInsertedObjects = NO;
	self.disksArrayController.avoidsEmptySelection = NO;
	self.disksArrayController.sortDescriptors = self.appController.sortDescriptors;
	[self.disksArrayController bind:@"contentSet" toObject:self.arbitrator withKeyPath:@"disks" options:nil];
}

- (void)setupTableBindings
{
	[self.tableView bind:@"selectionIndexes" toObject:self.disksArrayController
			withKeyPath:@"selectionIndexes" options:nil];
}

- (Disk *)selectedDisk
{
	NSIndexSet *indexes = self.disksArrayController.selectionIndexes;
	if (indexes.count == 1) {
		NSArray *items = self.disksArrayController.arrangedObjects;
		if (indexes.lastIndex < items.count) return items[indexes.lastIndex];
	}
	return nil;
}

#pragma mark - Refresh

- (void)refreshDisplays
{
	if (!self.modeHeadlineLabel) return;

	BOOL activated = self.arbitrator.isActivated;
	NSString *headline;
	NSInteger segment;
	NSString *statusValue;
	NSString *shieldValue;

	NSString *descriptionText;
	switch (self.arbitrator.mountMode) {
		case MM_READONLY:
			headline = NSLocalizedString(@"Read-Only Mode Active", nil);
			descriptionText = NSLocalizedString(@"System automatically mounts attached volumes with read-only safeguards.", nil);
			segment = 1; statusValue = NSLocalizedString(@"READ-ONLY", nil); break;
		case MM_BLOCK:
		default:
			headline = NSLocalizedString(@"Block Mounts Mode Active", nil);
			descriptionText = NSLocalizedString(@"System rejects all automatic mount requests. Attached disks remain unmounted.", nil);
			segment = 0; statusValue = activated ? NSLocalizedString(@"ARMED", nil) : NSLocalizedString(@"INACTIVE", nil); break;
	}
	if (!activated) {
		headline = NSLocalizedString(@"Deactivated", nil);
		descriptionText = NSLocalizedString(@"Disk arbitration is deactivated. Disks mount according to standard macOS policy.", nil);
		statusValue = NSLocalizedString(@"INACTIVE", nil);
		segment = 2;
	}
	self.modeHeadlineLabel.stringValue = headline;
	self.modeDescriptionLabel.stringValue = descriptionText;
	self.modeSegmentControl.selectedSegment = segment;
	self.modeSegmentControl.enabled = YES;

	// Telemetry
	if (activated) shieldValue = @"100%";
	else shieldValue = @"0%";

	NSUInteger volumeCount = 0;
	NSUInteger externalCount = 0;
	NSUInteger imageCount = 0;
	NSUInteger rejectionCount = 0;
	for (Disk *disk in self.arbitrator.disks) {
		if (disk.isMountable) {
			volumeCount++;
			if (disk.isRemovable) externalCount++;
			if (disk.isDiskImage) imageCount++;
		}
		if (disk.rejectedMount) rejectionCount++;
	}

	self.telemetryStatusValue.stringValue = statusValue;
	self.telemetryShieldValue.stringValue = shieldValue;
	self.telemetryDevicesValue.stringValue = [NSString stringWithFormat:@"%lu Disks (%lu Vols)",
											  (unsigned long)self.arbitrator.disks.count,
											  (unsigned long)volumeCount];

	self.badgeAllCount.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)volumeCount];
	self.badgeExternalCount.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)externalCount];
	self.badgeImagesCount.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)imageCount];
	self.badgeRejectionsCount.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)rejectionCount];

	self.launchAgentStatusLabel.stringValue = self.appController.hasUserLaunchAgent ?
		NSLocalizedString(@"Active", nil) : NSLocalizedString(@"Inactive", nil);
	self.launchAgentStatusLabel.textColor = self.appController.hasUserLaunchAgent ?
		NSColor.systemGreenColor : NSColor.secondaryLabelColor;

	[self.tableView reloadData];
	[self updateInspectorForSelectedDisk:self.selectedDisk];
}

- (void)updateInspectorForSelectedDisk:(Disk *)disk
{
	if (!disk) {
		self.inspectorTitleLabel.stringValue = NSLocalizedString(@"Disk Inspector", nil);
		self.inspectorBSDName.stringValue = @"—";
		self.inspectorMountPath.stringValue = @"—";
		self.inspectorMediaKind.stringValue = @"—";
		self.inspectorMediaProtocol.stringValue = @"—";
		self.inspectorBlockSize.stringValue = @"—";
		self.inspectorVendor.stringValue = @"—";
		self.inspectorModel.stringValue = @"—";
		self.inspectorRemovable.stringValue = @"—";
		self.inspectorEjectable.stringValue = @"—";
		return;
	}
	self.inspectorTitleLabel.stringValue = disk.BSDName ?: NSLocalizedString(@"Disk Inspector", nil);
	self.inspectorBSDName.stringValue = disk.BSDName ?: @"—";
	self.inspectorMountPath.stringValue = disk.uiMountPath;
	self.inspectorMediaKind.stringValue = disk.uiMediaKind ?: @"—";
	self.inspectorMediaProtocol.stringValue = disk.uiProtocol;
	self.inspectorBlockSize.stringValue = disk.uiBlockSize;
	self.inspectorVendor.stringValue = disk.uiVendor;
	self.inspectorModel.stringValue = disk.uiModel;
	self.inspectorRemovable.stringValue = disk.isRemovable ? NSLocalizedString(@"Yes", nil) : NSLocalizedString(@"No", nil);
	self.inspectorEjectable.stringValue = disk.isEjectable ? NSLocalizedString(@"Yes", nil) : NSLocalizedString(@"No", nil);
}

#pragma mark - Table delegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateInspectorForSelectedDisk:self.selectedDisk];
}

@end
