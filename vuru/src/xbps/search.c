#include "search.h"
#include <stdio.h>
#include <string.h>
#include <strings.h>

/**
 * Case-insensitive substring search.
 */
static int contains_ignore_case(const char *haystack, const char *needle) {
  if (!haystack || !needle)
    return 0;
  return strcasestr(haystack, needle) != NULL;
}

void xbps_search(Index *idx, const char *query) {
  if (!idx || !idx->json || !query) {
    return;
  }

  // Count matches first
  int count = 0;
  cJSON *item = NULL;

  cJSON_ArrayForEach(item, idx->json) {
    if (!item->string)
      continue;

    if (contains_ignore_case(item->string, query)) {
      count++;
      continue;
    }

    // Also search in description if available
    cJSON *desc = cJSON_GetObjectItem(item, "short_desc");
    if (desc && cJSON_IsString(desc) &&
        contains_ignore_case(desc->valuestring, query)) {
      count++;
    }
  }

  if (count == 0) {
    printf("No packages found matching '%s'\n", query);
    return;
  }

  printf("\n%-24s %-15s %-20s\n", "PACKAGE", "VERSION", "CATEGORY");
  printf("-------------------------------------------------------------\n");

  cJSON_ArrayForEach(item, idx->json) {
    if (!item->string)
      continue;

    int match = contains_ignore_case(item->string, query);

    if (!match) {
      cJSON *desc = cJSON_GetObjectItem(item, "short_desc");
      if (desc && cJSON_IsString(desc)) {
        match = contains_ignore_case(desc->valuestring, query);
      }
    }

    if (match) {
      cJSON *ver = cJSON_GetObjectItem(item, "version");
      cJSON *cat = cJSON_GetObjectItem(item, "category");

      const char *ver_str =
          (ver && cJSON_IsString(ver)) ? ver->valuestring : "?";
      const char *cat_str =
          (cat && cJSON_IsString(cat)) ? cat->valuestring : "?";

      printf("%-24s %-15s %-20s\n", item->string, ver_str, cat_str);
    }
  }

  printf("\n%d package(s) found\n", count);
}
