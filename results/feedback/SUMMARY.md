1 crash submission(s), newest first

## 1. 2026-10-30T01:11:25.557Z · build 15 · iPhone12_1 · iOS 26.6.1
{
 "createdDate": "2026-10-30T01:11:25.557Z",
 "deviceModel": "iPhone12_1",
 "osVersion": "26.6.1",
 "architecture": "arm64e",
 "appPlatform": "IOS",
 "devicePlatform": "IOS",
 "deviceFamily": "IPHONE",
 "batteryPercentage": 90,
 "connectionType": "WIFI",
 "buildBundleId": "org.periopsignal.app",
 "build": "15"
}
Version:             1.5.1 (15)
OS Version:          iPhone OS 26.6.1 (23G83)
Exception Type:  EXC_CRASH (SIGABRT)
Exception Codes: 0x0000000000000000, 0x0000000000000000
Termination Reason: SIGNAL 6 Abort trap: 6
Triggered by Thread:  0
Thread 0 Crashed:
0   libsystem_kernel.dylib        	0x000000024902f1d0 __pthread_kill + 8 (:-1)
1   libsystem_pthread.dylib       	0x00000001f93857dc pthread_kill + 268 (:-1)
2   libsystem_c.dylib             	0x00000001a55c6fcc abort + 148 (:-1)
3   libswiftCore.dylib            	0x000000019675a88c swift::fatalErrorv(unsigned int, char const*, char*) + 144 (:-1)
4   libswiftCore.dylib            	0x000000019675a7fc swift::fatalError(unsigned int, char const*, ...) + 32 (:-1)
5   libswiftCore.dylib            	0x00000001966cf074 swift::runtime::AccessSet::insert(swift::runtime::Access*, void*, void*, swift::ExclusivityFlags) + 572 (:-1)
6   libswiftCore.dylib            	0x00000001966ced8c swift_beginAccess + 84 (:-1)
7   PeriopSignal                  	0x0000000100a43d70 AclsStore.state.getter + 20 (@__swiftmacro_12PeriopSignal9AclsStoreC5state18ObservationTrackedfMa_.swift:8)
8   PeriopSignal                  	0x0000000100a43d70 AclsStore.t.getter + 204 (AclsView.swift:21)
9   PeriopSignal                  	0x0000000100a4e740 closure #2 in closure #3 in closure #2 in AclsView.clockBar(_:_:_:_:) + 664 (AclsView.swift:184)
10  SwiftUICore                   	0x00000001a3d66f50 <deduplicated_symbol> + 28
11  SwiftUICore                   	0x00000001a45a0888 FunctionalLocation.set(_:transaction:) + 28 (:-1)
12  SwiftUICore                   	0x00000001a40213dc LocationBox.set(_:transaction:) + 296 (:-1)
13  SwiftUICore                   	0x00000001a45a04f8 protocol witness for Location.set(_:transaction:) in conformance LocationBox<A> + 24 (:-1)
14  SwiftUICore                   	0x00000001a45a0778 ProjectedLocation.set(_:transaction:) + 588 (:-1)
15  SwiftUICore                   	0x00000001a40213dc LocationBox.set(_:transaction:) + 296 (:-1)
16  SwiftUI                       	0x00000001a384b780 specialized Binding.wrappedValue.setter + 12 (:-1)
17  SwiftUI                       	0x00000001a384b780 closure #2 in ResolvedSegmentedControl.init(selectedIndices:segments:) + 88 (:-1)
18  SwiftUICore                   	0x00000001a3d66f50 <deduplicated_symbol> + 28
19  SwiftUICore                   	0x00000001a45a0888 FunctionalLocation.set(_:transaction:) + 28 (:-1)
20  SwiftUICore                   	0x00000001a40213dc LocationBox.set(_:transaction:) + 296 (:-1)
21  SwiftUICore                   	0x00000001a4021454 Binding.ScopedLocation.set(_:transaction:) + 48 (:-1)
22  SwiftUICore                   	0x00000001a40213dc LocationBox.set(_:transaction:) + 296 (:-1)
23  SwiftUICore                   	0x00000001a4021454 Binding.ScopedLocation.set(_:transaction:) + 48 (:-1)
24  SwiftUICore                   	0x00000001a40213dc LocationBox.set(_:transaction:) + 296 (:-1)
25  SwiftUI                       	0x00000001a31362ac specialized Binding.wrappedValue.setter + 12 (:-1)
26  SwiftUI                       	0x00000001a31362ac SegmentedControlCoordinator.selectionChanged(_:) + 116
27  SwiftUI                       	0x00000001a3136350 @objc SegmentedControlCoordinator.selectionChanged(_:) + 60 (:-1)
28  UIKitCore                     	0x000000019fb8deb0 _UIPerformVoidSelector2 + 36 (:-1)
29  UIKitCore                     	0x000000019fb8deb0 -[UIApplication sendAction:to:from:forEvent:] + 100 (:-1)
30  UIKitCore                     	0x000000019fcbdf2c -[UIControl sendAction:to:forEvent:] + 108 (:-1)
31  UIKitCore                     	0x000000019fc357dc -[UIControl _sendActionsForEvents:withEvent:] + 380 (:-1)
32  UIKitCore                     	0x000000019f721a14 -[_UIAfterCACommitBlock run] + 72 (:-1)
33  UIKitCore                     	0x000000019f721948 -[_UIAfterCACommitQueue flush] + 160 (:-1)
34  UIKitCore                     	0x000000019f721860 _runAfterCACommitDeferredBlocks + 260 (:-1)
35  UIKitCore                     	0x000000019f721e9c _cleanUpAfterCAFlushAndRunDeferredBlocks + 80 (:-1)
36  UIKitCore                     	0x000000019f6f6604 _UIApplicationFlushCATransaction + 72 (:-1)
37  UIKitCore                     	0x000000019f6f6524 performCATransactionCommitAction + 308 (:-1)
38  UIKitCore                     	0x000000019f6f6524 __setupUpdateSequence_block_invoke_2 + 352 (:-1)
(full log: crash-1.txt)
