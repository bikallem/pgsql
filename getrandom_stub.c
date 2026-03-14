#include <moonbit.h>

#if defined(__linux__) || defined(__APPLE__)
#include <sys/random.h>
#elif defined(_WIN32)
#include <windows.h>
#include <bcrypt.h>
#endif

// Fill buf with cryptographically secure random bytes.
// Returns 0 on success, -1 on failure.
int pgsql_getrandom(unsigned char *buf, int len) {
#if defined(__linux__)
  ssize_t n = getrandom(buf, (size_t)len, 0);
  return (n == (ssize_t)len) ? 0 : -1;
#elif defined(__APPLE__)
  return getentropy(buf, (size_t)len);
#elif defined(_WIN32)
  NTSTATUS status = BCryptGenRandom(NULL, (PUCHAR)buf, (ULONG)len,
                                    BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  return (status >= 0) ? 0 : -1;
#else
  (void)buf;
  (void)len;
  return -1;
#endif
}
