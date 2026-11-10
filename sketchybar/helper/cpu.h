#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <time.h>

#define MAX_TOPPROC_LEN 11 // glyphs; 11 x 5.1pt (GeistMono 8.5) fits the 58pt label

static const char TOPPROC[] = { "/bin/ps -Aceo pid,pcpu,comm -r" }; 
static const char FILTER_PATTERN[] = { "com.apple." };

struct cpu {
  host_t host;
  mach_msg_type_number_t count;
  host_cpu_load_info_data_t load;
  host_cpu_load_info_data_t prev_load;
  bool has_prev_load;

  char command[256];
};

static inline void cpu_init(struct cpu* cpu) {
  cpu->host = mach_host_self();
  cpu->count = HOST_CPU_LOAD_INFO_COUNT;
  cpu->has_prev_load = false;
  snprintf(cpu->command, 100, "");
}

static inline void cpu_update(struct cpu* cpu) {
  kern_return_t error = host_statistics(cpu->host,
                                        HOST_CPU_LOAD_INFO,
                                        (host_info_t)&cpu->load,
                                        &cpu->count                );

  if (error != KERN_SUCCESS) {
    printf("Error: Could not read cpu host statistics.\n");
    return;
  }

  if (cpu->has_prev_load) {
    uint32_t delta_user = cpu->load.cpu_ticks[CPU_STATE_USER]
                          - cpu->prev_load.cpu_ticks[CPU_STATE_USER];

    uint32_t delta_system = cpu->load.cpu_ticks[CPU_STATE_SYSTEM]
                            - cpu->prev_load.cpu_ticks[CPU_STATE_SYSTEM];

    uint32_t delta_idle = cpu->load.cpu_ticks[CPU_STATE_IDLE]
                          - cpu->prev_load.cpu_ticks[CPU_STATE_IDLE];

    double user_perc = (double)delta_user / (double)(delta_system
                                                     + delta_user
                                                     + delta_idle);

    double sys_perc = (double)delta_system / (double)(delta_system
                                                      + delta_user
                                                      + delta_idle);

    double total_perc = user_perc + sys_perc;

    FILE* file;
    char line[1024];

    file = popen(TOPPROC, "r");
    if (!file) {
      printf("Error: TOPPROC command errored out...\n" );
      return;
    }

    fgets(line, sizeof(line), file);
    fgets(line, sizeof(line), file);

    // "  pid  pcpu comm" -> just the command name, without a com.apple. prefix,
    // shortened to MAX_TOPPROC_LEN with an ellipsis. Single quotes are dropped
    // because the name is passed to sketchybar inside '...'.
    char name[1024] = { 0 };
    int pid; float pcpu;
    if (sscanf(line, " %d %f %1023[^\n]", &pid, &pcpu, name) < 3) name[0] = '\0';
    char* comm = name;
    if (strncmp(comm, FILTER_PATTERN, strlen(FILTER_PATTERN)) == 0) comm += strlen(FILTER_PATTERN);

    char topproc[MAX_TOPPROC_LEN + 4];
    uint32_t caret = 0;
    for (char* c = comm; *c && caret < MAX_TOPPROC_LEN; c++) {
      if (*c == '\'') continue;
      topproc[caret++] = *c;
    }
    if (strlen(comm) > MAX_TOPPROC_LEN) {
      // one-glyph ellipsis (UTF-8) after MAX_TOPPROC_LEN - 1 chars
      caret = MAX_TOPPROC_LEN - 1;
      memcpy(topproc + caret, "\xe2\x80\xa6", 3);
      caret += 3;
    }
    topproc[caret] = '\0';

    pclose(file);

    char color[16];
    if (total_perc >= .7) {
      snprintf(color, 16, "%s", getenv("RED"));
    } else if (total_perc >= .3) {
      snprintf(color, 16, "%s", getenv("ORANGE"));
    } else if (total_perc >= .1) {
      snprintf(color, 16, "%s", getenv("YELLOW"));
    } else {
      snprintf(color, 16, "%s", getenv("LABEL_COLOR"));
    }

    snprintf(cpu->command, 256, "--push cpu.graph %.2f "
                                "--set cpu.top label='%s' "
                                "--set cpu.percent label=%.0f%% label.color=%s ",
                                total_perc,
                                topproc,
                                total_perc*100.,
                                color          );
  }
  else {
    snprintf(cpu->command, 256, "");
  }

  cpu->prev_load = cpu->load;
  cpu->has_prev_load = true;
}
