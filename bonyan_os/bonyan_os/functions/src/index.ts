// functions/src/index.ts
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — Cloud Functions (Node.js 20 / TypeScript)   ║
// ║  Badge Degradation · Admin Elevation · Agora Token · FCM    ║
// ╚══════════════════════════════════════════════════════════════╝

import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import * as crypto from "crypto";
import { RtcTokenBuilder, RtcRole } from "agora-access-token";

admin.initializeApp();
const db  = admin.firestore();
const rtdb = admin.database();

// ── Secrets (stored in Firebase Secret Manager, never in code) ──────────────
const SUPER_ADMIN_SECRET   = defineSecret("SUPER_ADMIN_ELEVATION_SECRET");
const ADMIN_TOTP_SEED      = defineSecret("ADMIN_TOTP_SEED");
const AGORA_APP_ID         = defineSecret("AGORA_APP_ID");
const AGORA_APP_CERTIFICATE = defineSecret("AGORA_APP_CERTIFICATE");

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 1 — SUPER-ADMIN ELEVATION (Callable)
// Verifies secret + TOTP server-side, mints Custom Claim if valid.
// All attempts are logged for audit.
// ─────────────────────────────────────────────────────────────────────────────

export const requestSuperAdminElevation = functions.https.onCall(
  { secrets: [SUPER_ADMIN_SECRET, ADMIN_TOTP_SEED], region: "me-central1" },
  async (request) => {
    // Must be authenticated
    if (!request.auth) {
      throw new functions.https.HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const uid           = request.auth.uid;
    const elevationCode = request.data.elevationCode as string;
    const mfaToken      = request.data.mfaToken      as string;

    // Log every attempt regardless of outcome
    await db.collection("adminElevationAudit").add({
      uid,
      attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      ip: request.rawRequest?.ip ?? "unknown",
      userAgent: request.rawRequest?.headers?.["user-agent"] ?? "unknown",
    });

    // Rate limit: max 3 attempts per hour per UID
    const hourAgo = new Date(Date.now() - 3600 * 1000);
    const recentAttempts = await db.collection("adminElevationAudit")
      .where("uid", "==", uid)
      .where("attemptedAt", ">", hourAgo)
      .count()
      .get();

    if (recentAttempts.data().count > 3) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "تجاوزت الحد المسموح من المحاولات. حاول بعد ساعة"
      );
    }

    // Verify elevation code (constant-time comparison to prevent timing attacks)
    const storedSecret  = SUPER_ADMIN_SECRET.value();
    const provided      = crypto.createHash("sha256").update(elevationCode).digest("hex");
    const expected      = crypto.createHash("sha256").update(storedSecret).digest("hex");
    const codeValid     = crypto.timingSafeEqual(Buffer.from(provided), Buffer.from(expected));

    // Verify TOTP (6-digit time-based OTP)
    const totpValid = verifyTotp(mfaToken, ADMIN_TOTP_SEED.value());

    if (!codeValid || !totpValid) {
      // Log failed attempt with outcome
      await db.collection("adminElevationAudit").add({
        uid, outcome: "DENIED", reason: !codeValid ? "wrong_code" : "wrong_totp",
        attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { success: false, messageAr: "رمز الوصول أو رمز التحقق غير صحيح. تم تسجيل المحاولة." };
    }

    // Grant Super-Admin Custom Claim
    await admin.auth().setCustomUserClaims(uid, {
      role: "superAdmin",
      elevatedAt: new Date().toISOString(),
      elevatedBy: "cloud-function",
    });

    await db.collection("adminElevationAudit").add({
      uid, outcome: "GRANTED",
      attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    functions.logger.warn(`⚠️ Super-Admin elevation GRANTED to ${uid}`);
    return { success: true, messageAr: "تم منح صلاحيات المشرف العام بنجاح ✅" };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 2 — BADGE DEGRADATION (Scheduled: daily at 3am Riyadh)
// ─────────────────────────────────────────────────────────────────────────────

export const dailyBadgeDegradation = functions.scheduler.onSchedule(
  { schedule: "0 0 * * *", timeZone: "Asia/Riyadh", region: "me-central1" },
  async () => {
    functions.logger.info("🏅 Running daily badge degradation check...");
    const now = new Date();

    // Stream all students in batches
    const studentsSnap = await db.collection("students")
      .where("role", "==", "student")
      .select("uid", "schoolId")
      .get();

    const batchSize = 50;
    const studentDocs = studentsSnap.docs;

    for (let i = 0; i < studentDocs.length; i += batchSize) {
      const chunk = studentDocs.slice(i, i + batchSize);
      await Promise.all(chunk.map(sd => _processBadgesForStudent(sd.id, now)));
    }

    functions.logger.info(`✅ Badge degradation complete — ${studentDocs.length} students processed`);
  }
);

async function _processBadgesForStudent(uid: string, now: Date): Promise<void> {
  const badgesSnap = await db.collection("students").doc(uid)
    .collection("badges")
    .where("isEarned", "==", true)
    .where("isRevoked", "==", false)
    .get();

  const batch = db.batch();
  const fcmTokens: string[] = [];

  for (const badgeDoc of badgesSnap.docs) {
    const data = badgeDoc.data();
    const lastActivity = data.lastActivityAt?.toDate() ?? new Date(0);
    const daysSince    = Math.floor((now.getTime() - lastActivity.getTime()) / 86_400_000);

    // Badge catalogue config (mirrors Dart BadgeCatalogue)
    const config = BADGE_CONFIG[badgeDoc.id];
    if (!config) continue;

    if (daysSince >= config.revokeAfterDays) {
      batch.update(badgeDoc.ref, {
        isRevoked: true, isEarned: false,
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      fcmTokens.push(...await _getStudentFcmTokens(uid));
      await _sendBadgeRevokedNotification(uid, config.nameAr, daysSince);

    } else if (daysSince >= config.degradeAfterDays) {
      batch.update(badgeDoc.ref, { isWarned: true });
      await _sendBadgeWarningNotification(uid, config.nameAr, config.revokeAfterDays - daysSince);
    }
  }

  await batch.commit();
}

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 3 — AGORA TOKEN GENERATOR (Callable)
// Generates time-limited RTC token server-side. Client never holds secret.
// ─────────────────────────────────────────────────────────────────────────────

export const generateAgoraToken = functions.https.onCall(
  { secrets: [AGORA_APP_ID, AGORA_APP_CERTIFICATE], region: "me-central1" },
  async (request) => {
    if (!request.auth) {
      throw new functions.https.HttpsError("unauthenticated", "المصادقة مطلوبة");
    }

    const channelId = request.data.channelId as string;
    if (!channelId || channelId.length > 64) {
      throw new functions.https.HttpsError("invalid-argument", "معرف القناة غير صالح");
    }

    // Token valid for 1 hour
    const expirySeconds = Math.floor(Date.now() / 1000) + 3600;
    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID.value(),
      AGORA_APP_CERTIFICATE.value(),
      channelId,
      0, // uid 0 = any user
      RtcRole.PUBLISHER,
      expirySeconds,
    );

    functions.logger.info(`📞 Agora token generated for channel ${channelId} by ${request.auth.uid}`);
    return { token, expiresAt: expirySeconds };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 4 — CELL CASCADE NOTIFY (Realtime DB trigger)
// Fires when alarm escalation node is written → sends FCM to all cell members
// ─────────────────────────────────────────────────────────────────────────────

export const onCellAlarmEscalation = functions.database.onValueCreated(
  {
    ref: "/cells/{cellId}/alarms/{alarmId}/escalation",
    region: "me-central1",
  },
  async (event) => {
    const cellId  = event.params.cellId;
    const alarmId = event.params.alarmId;
    const data    = event.data.val() as {
      step: string;
      absentMemberIds: string[];
      triggeredAt: string;
    };

    functions.logger.info(`🔔 Cascade escalation for cell ${cellId} — step: ${data.step}`);

    if (!data.absentMemberIds?.length) return;

    // Fetch FCM tokens for all PRESENT cell members (they need to help wake the absent ones)
    const cellSnap = await db.collection("cells").doc(cellId).get();
    const cellData = cellSnap.data();
    if (!cellData) return;

    const allMemberIds: string[] = cellData.memberIds ?? [];
    const presentMemberIds = allMemberIds.filter(
      (id) => !data.absentMemberIds.includes(id)
    );

    const absentNames: string[] = [];
    for (const uid of data.absentMemberIds) {
      const studentSnap = await db.collection("students").doc(uid).get();
      const name = studentSnap.data()?.displayName ?? "زميل";
      absentNames.push(name);
    }

    // FCM to present members: "wake up your friends"
    const presentTokens = (
      await Promise.all(presentMemberIds.map(_getStudentFcmTokens))
    ).flat();

    if (presentTokens.length) {
      await admin.messaging().sendEachForMulticast({
        tokens: presentTokens,
        notification: {
          title: "⚠️ مجموعتك تحتاجك!",
          body: `${absentNames.join("، ")} لم يسجل حضوره للفجر. ساعد مجموعتك 🕌`,
        },
        android: {
          priority: "high",
          notification: { channelId: "bonyan_alarm_channel", sound: "fajr_adhan" },
        },
        apns: {
          payload: { aps: { sound: "fajr_adhan.caf", badge: 1 } },
        },
        data: {
          type: "cell_cascade",
          cellId,
          alarmId,
          absentMemberIds: JSON.stringify(data.absentMemberIds),
        },
      });
    }

    // FCM to absent members: urgent wake-up
    const absentTokens = (
      await Promise.all(data.absentMemberIds.map(_getStudentFcmTokens))
    ).flat();

    if (absentTokens.length) {
      await admin.messaging().sendEachForMulticast({
        tokens: absentTokens,
        notification: {
          title: "🌙 وقت الفجر — مجموعتك تنتظرك!",
          body: "صلِّ الفجر وسجّل حضورك. مجموعتك في انتظارك 🤲",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "bonyan_alarm_channel",
            sound: "fajr_adhan",
            sticky: true,
          },
        },
        data: {
          type: "urgent_wakeup",
          cellId,
          alarmId,
          screen: "/alarm",
        },
      });
    }

    functions.logger.info(`✅ Cascade FCM sent — ${presentTokens.length} present, ${absentTokens.length} absent`);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 5 — PARENT NOTIFY (Realtime DB trigger)
// ─────────────────────────────────────────────────────────────────────────────

export const onParentAlertTriggered = functions.database.onValueCreated(
  {
    ref: "/cells/{cellId}/alarms/{alarmId}/parentAlert",
    region: "me-central1",
  },
  async (event) => {
    const data = event.data.val() as {
      absentMemberIds: string[];
      alarmLabel: string;
    };

    for (const studentId of data.absentMemberIds) {
      // Find parent linked to this student
      const parentSnap = await db.collection("users")
        .where("parentOf", "==", studentId)
        .where("role", "==", "parent")
        .limit(1)
        .get();

      if (parentSnap.empty) continue;

      const parentTokens = await _getStudentFcmTokens(parentSnap.docs[0].id);
      const studentSnap  = await db.collection("students").doc(studentId).get();
      const studentName  = studentSnap.data()?.displayName ?? "ابنك/ابنتك";

      if (parentTokens.length) {
        await admin.messaging().sendEachForMulticast({
          tokens: parentTokens,
          notification: {
            title: `تنبيه: ${studentName} 🕌`,
            body: `لم يسجّل ${studentName} حضوره لـ${data.alarmLabel} حتى الآن. تواصل معه.`,
          },
          data: { type: "parent_alert", studentId },
        });
      }
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 6 — LEADERBOARD RECALCULATION (Firestore trigger)
// Fires whenever a student's coinBalance changes → recompute school rank
// ─────────────────────────────────────────────────────────────────────────────

export const onCoinBalanceChanged = functions.firestore.onDocumentUpdated(
  { document: "students/{studentId}", region: "me-central1" },
  async (event) => {
    const before = event.data?.before.data();
    const after  = event.data?.after.data();
    if (!before || !after) return;

    const balanceChanged = before.coinBalance !== after.coinBalance;
    const schoolId = after.schoolId as string;
    if (!balanceChanged || !schoolId) return;

    // Update cell collective score
    const cellId = after.cellId as string | undefined;
    if (cellId) {
      await _recalculateCellScore(cellId);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 7 — ATTENDANCE HEATMAP AGGREGATION (Scheduled: daily midnight)
// ─────────────────────────────────────────────────────────────────────────────

export const aggregateDailyAttendance = functions.scheduler.onSchedule(
  { schedule: "59 23 * * *", timeZone: "Asia/Riyadh", region: "me-central1" },
  async () => {
    const today = new Date().toISOString().split("T")[0];
    const schoolsSnap = await db.collection("schools").get();

    for (const schoolDoc of schoolsSnap.docs) {
      const schoolId = schoolDoc.id;
      const sessionsSnap = await db.collection("attendanceSessions")
        .where("schoolId", "==", schoolId)
        .where("date", "==", today)
        .get();

      let totalPresent = 0, totalStudents = 0;
      for (const session of sessionsSnap.docs) {
        const records = session.data().records ?? {};
        const vals = Object.values(records) as any[];
        totalPresent   += vals.filter(v => v.status === "present" || v.status === "late").length;
        totalStudents  += vals.length;
      }

      const rate = totalStudents > 0 ? totalPresent / totalStudents : 0;
      await db.collection("schools").doc(schoolId)
        .collection("dailyStats")
        .doc(today)
        .set({ date: today, attendanceRate: rate, totalStudents, totalPresent }, { merge: true });
    }

    functions.logger.info("✅ Daily attendance aggregation complete");
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

async function _getStudentFcmTokens(uid: string): Promise<string[]> {
  const tokenSnap = await db.collection("fcmTokens").doc(uid).get();
  if (!tokenSnap.exists) return [];
  const data = tokenSnap.data()!;
  return (data.tokens as string[] | undefined) ?? [];
}

async function _sendBadgeRevokedNotification(uid: string, badgeNameAr: string, days: number): Promise<void> {
  const tokens = await _getStudentFcmTokens(uid);
  if (!tokens.length) return;
  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: `⬇️ شارة "${badgeNameAr}" سُحبت منك`,
      body: `مرّت ${days} أيام دون انتظام. استعد نشاطك لاسترداد شارتك 💪`,
    },
    data: { type: "badge_revoked", badgeNameAr },
  });
}

async function _sendBadgeWarningNotification(uid: string, badgeNameAr: string, daysLeft: number): Promise<void> {
  const tokens = await _getStudentFcmTokens(uid);
  if (!tokens.length) return;
  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: `⚠️ شارة "${badgeNameAr}" في خطر!`,
      body: `باقي ${daysLeft} أيام قبل سحب الشارة. واصل انتظامك ⭐`,
    },
    data: { type: "badge_warning", badgeNameAr },
  });
}

async function _recalculateCellScore(cellId: string): Promise<void> {
  const cellSnap = await db.collection("cells").doc(cellId).get();
  const memberIds: string[] = cellSnap.data()?.memberIds ?? [];
  if (!memberIds.length) return;

  const memberData = await Promise.all(
    memberIds.map(id => db.collection("students").doc(id).get())
  );

  const scores = memberData.map(snap => {
    const d = snap.data() ?? {};
    const attendance = (d.attendanceRate as number ?? 0);
    const gpa        = (d.gpa as number ?? 0) / 100;
    const prayer     = (d.prayerConsistency as number ?? 0);
    return (attendance * 0.4) + (gpa * 0.4) + (prayer * 0.2);
  });

  const avgScore = scores.reduce((a, b) => a + b, 0) / scores.length * 100;
  await rtdb.ref(`cells/${cellId}/collectiveScore`).set(Math.round(avgScore));
}

// TOTP verification (RFC 6238 compliant)
function verifyTotp(token: string, seed: string): boolean {
  const window = 1; // ±30 seconds window
  const timeStep = 30;
  const now = Math.floor(Date.now() / 1000);

  for (let w = -window; w <= window; w++) {
    const counter = Math.floor((now + w * timeStep) / timeStep);
    const counterBuffer = Buffer.alloc(8);
    counterBuffer.writeBigInt64BE(BigInt(counter));
    const hmac = crypto.createHmac("sha1", Buffer.from(seed, "base64"))
      .update(counterBuffer).digest();
    const offset = hmac[hmac.length - 1] & 0x0f;
    const code = ((hmac.readUInt32BE(offset) & 0x7fffffff) % 1000000)
      .toString().padStart(6, "0");
    if (code === token) return true;
  }
  return false;
}

// Badge configuration (mirrors Dart BadgeCatalogue)
const BADGE_CONFIG: Record<string, { nameAr: string; degradeAfterDays: number; revokeAfterDays: number }> = {
  "fajr_knight":      { nameAr: "فارس الفجر",      degradeAfterDays: 3,  revokeAfterDays: 5  },
  "prayers_guardian": { nameAr: "حارس الصلوات",     degradeAfterDays: 2,  revokeAfterDays: 4  },
  "azkar_master":     { nameAr: "حصن الأذكار",      degradeAfterDays: 3,  revokeAfterDays: 6  },
  "scholar":          { nameAr: "طالب العلم",        degradeAfterDays: 7,  revokeAfterDays: 14 },
  "study_warrior":    { nameAr: "محارب المذاكرة",    degradeAfterDays: 3,  revokeAfterDays: 5  },
  "quiz_champion":    { nameAr: "بطل الاختبارات",    degradeAfterDays: 30, revokeAfterDays: 60 },
  "cell_anchor":      { nameAr: "عماد الخلية",       degradeAfterDays: 7,  revokeAfterDays: 14 },
  "peer_mentor":      { nameAr: "المرشد",            degradeAfterDays: 14, revokeAfterDays: 30 },
  "punctual":         { nameAr: "دائم الحضور",       degradeAfterDays: 2,  revokeAfterDays: 3  },
};
