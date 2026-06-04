import 'package:hugeicons/hugeicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MilestoneInfo {
  final int count;
  final String title;
  final List<List<dynamic>> icon;
  final String? flavourText;

  const MilestoneInfo({
    required this.count,
    required this.title,
    required this.icon,
    this.flavourText,
  });
}

const kMilestones = <MilestoneInfo>[
  MilestoneInfo(count: 0,    title: 'Newcomer',        icon: HugeIcons.strokeRoundedEye),
  MilestoneInfo(count: 10,   title: 'The Curious',     icon: HugeIcons.strokeRoundedSearch01,     flavourText: "You've started asking the right questions."),
  MilestoneInfo(count: 25,   title: 'Pattern Spotter', icon: HugeIcons.strokeRoundedPuzzle,        flavourText: "You're beginning to see what others miss."),
  MilestoneInfo(count: 50,   title: 'Signal Chaser',   icon: HugeIcons.strokeRoundedSignalFull01,  flavourText: "The noise doesn't fool you anymore."),
  MilestoneInfo(count: 100,  title: 'Noise Canceller', icon: HugeIcons.strokeRoundedTarget01,      flavourText: "You cut through the chaos with precision."),
  MilestoneInfo(count: 250,  title: 'The Aligned',     icon: HugeIcons.strokeRoundedFlash,         flavourText: "Your perspective is razor sharp."),
  MilestoneInfo(count: 500,  title: 'Distortion Free', icon: HugeIcons.strokeRoundedDiamond01,     flavourText: "Reality is clear to you now."),
  MilestoneInfo(count: 1000, title: 'The Oracle',      icon: HugeIcons.strokeRoundedCrown,         flavourText: "You see what the world hasn't noticed yet."),
];

class MilestoneService {
  static MilestoneInfo currentMilestone(int count) {
    MilestoneInfo result = kMilestones.first;
    for (final m in kMilestones) {
      if (count >= m.count) result = m;
    }
    return result;
  }

  static MilestoneInfo? nextMilestone(int count) {
    for (final m in kMilestones) {
      if (count < m.count) return m;
    }
    return null;
  }

  static Future<List<int>> fetchSeenMilestones() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final data = await client
          .from('user_profiles')
          .select('seen_milestones')
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return [];
      final raw = data['seen_milestones'];
      if (raw == null) return [];
      return (raw as List).map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> markSeen(int milestoneCount) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final seen = await fetchSeenMilestones();
      if (!seen.contains(milestoneCount)) {
        seen.add(milestoneCount);
        await client
            .from('user_profiles')
            .update({'seen_milestones': seen})
            .eq('id', userId);
      }
    } catch (_) {}
  }

  /// Returns the lowest-threshold milestone the user crossed but hasn't seen a modal for.
  static Future<MilestoneInfo?> firstUnseenMilestone(int count) async {
    final seen = await fetchSeenMilestones();
    for (final m in kMilestones) {
      if (m.count == 0) continue; // Newcomer has no modal
      if (count >= m.count && !seen.contains(m.count)) return m;
    }
    return null;
  }
}
