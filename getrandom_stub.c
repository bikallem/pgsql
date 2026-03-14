#include <moonbit.h>

#ifdef __linux__
#include <sys/random.h>
#elif defined(__APPLE__)
#include <Security/SecRandom.h>
#elif defined(_WIN32)
#include <bcrypt.h>
#endif

// Fill buf with cryptographically secure random bytes.
// Returns 0 on success, -1 on failure.
int pgsql_getrandom(unsigned char *buf, int len) {
#ifdef __linux__
  ssize_t n = getrandom(buf, (size_t)len, 0);
  return (n == (ssize_t)len) ? 0 : -1;
#elif defined(__APPLE__)
  return SecRandomCopyBytes(kSecRandomDefault, (size_t)len, buf);
#elif defined(_WIN32)
  NTSTATUS status = BCryptGenRandom(NULL, buf, (ULONG)len,
                                    BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  return (status >= 0) ? 0 : -1;
#else
  (void)buf;
  (void)len;
  return -1;
#endif
}
