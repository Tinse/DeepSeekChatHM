import { ChatSession } from '../model/Types';
import { borderColor, Palette, softColor, subTextColor, textColor } from './common/Theme';
import { formatClock } from '../utils/TextUtils';

@Component
export struct SessionPanel {
  @Prop sessions: ChatSession[] = [];
  @Prop activeId: string = '';
  @Prop isDark: boolean = false;
  onSelect: (id: string) => void = () => {
  };
  onNew: () => void = () => {
  };
  onDelete: (id: string) => void = () => {
  };

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('对话')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(textColor(this.isDark))
        Blank()
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_add'))
            .width(16)
            .height(16)
            .fillColor(Palette.brand)
        }
        .width(30)
        .height(30)
        .backgroundColor(softColor(this.isDark))
        .onClick(() => {
          this.onNew();
        })
      }
      .width('100%')
      .padding({ left: 14, right: 8, top: 6, bottom: 4 })

      if (this.sessions.length === 0) {
        Column({ space: 6 }) {
          Text('还没有对话')
            .fontSize(14)
            .fontColor(subTextColor(this.isDark))
          Text('点击右上角 + 开始')
            .fontSize(12)
            .fontColor(subTextColor(this.isDark))
        }
        .width('100%')
        .padding({ top: 40 })
      } else {
        List({ space: 2 }) {
          ForEach(this.sessions, (session: ChatSession) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text(session.title.length > 0 ? session.title : '新对话')
                    .fontSize(14)
                    .fontColor(textColor(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(formatClock(session.updatedAt))
                    .fontSize(11)
                    .fontColor(subTextColor(this.isDark))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (session.id === this.activeId) {
                  Circle()
                    .width(6)
                    .height(6)
                    .fill(Palette.brand)
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor(session.id === this.activeId ? softColor(this.isDark) : Color.Transparent)
              .borderRadius(12)
              .onClick(() => {
                this.onSelect(session.id);
              })
              .bindMenu([
                {
                  value: '删除会话',
                  action: () => {
                    this.onDelete(session.id);
                  }
                }
              ])
            }
          }, (session: ChatSession) => session.id)
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 6, right: 6 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(this.isDark ? '#12151B' : '#FBFBFD')
    .border({ width: { right: 1 }, color: borderColor(this.isDark) })
  }
}
